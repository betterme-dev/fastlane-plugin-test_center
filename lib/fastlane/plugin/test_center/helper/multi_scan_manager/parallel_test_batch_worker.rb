module TestCenter
  module Helper
    module MultiScanManager
      class ParallelTestBatchWorker < TestBatchWorker
        require 'securerandom'
        require 'colorize'
        
        attr_reader :pid
        
        def initialize(options)
          super(options)
          @pipe_endpoint = nil
        end

        def state=(new_state)
          super(new_state)
        end

        def process_results
          # This is performed in the Parent process
          stop_test_status_monitor
          @pid = nil
          result = @reader.gets
          @reader.close
          passed = result.to_s.chomp == 'true'
          @options[:test_batch_results] << passed
          unless passed
            $stdout.puts("[worker #{@options[:batch_index] + 1}] Batch FAILED; details: #{@log_filepath}")
            $stdout.flush
          end
          self.state = :ready_to_work
        end

        def run(run_options)
          self.state = :working

          open_interprocess_communication
          @options[:buildlog_run_id] = "run-#{SecureRandom.hex(8)}"
          @monitor_log_path = File.join(@options[:buildlog_path], @options[:buildlog_run_id]) if @options[:buildlog_path]
          @pid = Process.fork do
            tests_passed = false
            begin
              reroute_stdout_to_logfile
              tests_passed = super(run_options)
            rescue StandardError => e
              puts e.message
              puts e.backtrace.inspect
            ensure
              print_final_results(tests_passed)
              handle_child_process_results(tests_passed)
              exit!
            end
          end
          close_parent_process_writer
          start_test_status_monitor if @monitor_log_path
        end

        def print_final_results(tests_passed)
          FastlaneCore::UI.verbose("All tests passed for batch #{@options[:batch_index] + 1}? #{tests_passed}")
        end

        def open_interprocess_communication
          # This is performed in the Parent process in preparation to setup
          # the STDOUT and STDOUT for printing messages from the Child process
          # to a file. This is done so that when multiple processes write
          # messages, they will not be written to the console in a broken
          # interlaced manner.
          @reader, @writer = IO.pipe
          @log_filepath = File.join(
            Dir.mktmpdir,
            "parallel-test-batch-#{@options[:batch_index] + 1}.txt"
          )
        end

        def reroute_stdout_to_logfile
          @reader.close # we are now in the subprocess. Write all stdout to the
          # log file to prevent interlaced messages
          @logfile = File.open(@log_filepath, 'w')
          @logfile.sync = true
          $stdout.reopen(@logfile)
          $stderr.reopen(@logfile)
        end

        def handle_child_process_results(tests_passed)
          # as suggested by the method name, this is done in the Child process
          @logfile.close
          @writer.puts tests_passed.to_s
          @writer.close
        end

        def close_parent_process_writer
          @writer.close
        end

        def start_test_status_monitor
          @stop_test_status_monitor = false
          @test_status_monitor = Thread.new do
            offsets = {}
            loop do
              read_test_statuses(offsets)
              break if @stop_test_status_monitor

              sleep 0.1
            end
          end
        end

        def stop_test_status_monitor
          return unless @test_status_monitor

          @stop_test_status_monitor = true
          @test_status_monitor.join
          @test_status_monitor = nil
        end

        def read_test_statuses(offsets)
          log_path = @monitor_log_path || @options[:buildlog_path]
          Dir.glob(File.join(log_path, '**', '*.log')).each do |path|
            File.open(path) do |log|
              current = log_cursor(path, log)
              previous = offsets[path]
              if previous && previous[:inode] == current[:inode] &&
                 previous[:offset] <= log.size &&
                 log.read(previous[:prefix].bytesize) == previous[:prefix]
                log.seek(previous[:offset], IO::SEEK_SET)
                current[:attempts] = previous[:attempts] || {}
              else
                log.rewind
                current[:attempts] = {}
              end
              while (line = log.gets)
                unless line.end_with?("\n")
                  log.seek(-line.bytesize, IO::SEEK_CUR)
                  break
                end
                if (attempt = line.match(/Test Case '-\[([^\]]+)\]' started \(Iteration (\d+) of (\d+)\)\./))
                  current[:attempts][attempt[1]] = [attempt[2].to_i, attempt[3].to_i]
                end
                status = test_status_from_xcodebuild(line, current[:attempts])
                if status
                  $stdout.puts(status)
                  $stdout.flush
                end
              end
              current[:offset] = log.pos
              offsets[path] = current
            end
          rescue Errno::ENOENT
            # A retry can replace the log between listing and opening it.
            offsets.delete(path)
          end
        end

        def log_cursor(path, log = nil)
          File.open(path) { |opened| return log_cursor(path, opened) } unless log

          start = log.pos
          log.rewind
          prefix = log.read(256) || ''
          log.seek(start, IO::SEEK_SET)
          { inode: log.stat.ino, prefix: prefix, offset: log.size }
        end

        def test_status_from_xcodebuild(line, attempts = {})
          match = line.match(/Test Case '-\[([^\]]+)\]' (passed|failed|skipped)(?: \(([^)]*)\))?\./)
          if match
            suite, test = match[1].split(' ', 2)
            return unless test

            status = match[2]
            duration = match[3]
            iteration = attempts[match[1]]
          else
            match = line.match(/Test case '(.+)\.([^.'()]+)\(\)' skipped on '[^']+'(?: \(([^)]*)\))?/)
            return unless match

            suite, test, duration = match.captures
            status = 'skipped'
            iteration = nil
          end
          description = "[#{suite.split('.').last}] #{test}"
          description += " (#{duration})" if duration
          if iteration && (status == 'failed' || (status == 'passed' && iteration[0] > 1))
            current, total = iteration
            description += " [attempt #{current}/#{total}]"
          end
          symbol = { 'passed' => '✓', 'failed' => '✗', 'skipped' => 'ø' }.fetch(status)
          result = "▸ #{symbol} #{description}"
          status == 'failed' ? result.red : result.magenta
        end
      end
    end
  end
end
