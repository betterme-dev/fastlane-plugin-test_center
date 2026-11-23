module TestCenter::Helper::MultiScanManager
  describe 'ParallelTestBatchWorker' do
    describe '#run' do
      before(:each) do
        allow_any_instance_of(ParallelTestBatchWorker).to receive(:open_interprocess_communication)
        allow_any_instance_of(ParallelTestBatchWorker).to receive(:close_parent_process_writer)
        allow_any_instance_of(ParallelTestBatchWorker).to receive(:reroute_stdout_to_logfile)
        allow_any_instance_of(ParallelTestBatchWorker).to receive(:handle_child_process_results)
        allow_any_instance_of(ParallelTestBatchWorker).to receive(:start_test_status_monitor)
      end

      it 'calls the parent class\'s #run method in a fork block' do
        worker = ParallelTestBatchWorker.new({ test_batch_results: [], batch_index: 1 })
        expect(worker).to receive(:exit!)
        expect(worker).to receive(:open_interprocess_communication)
        expect(Process).to receive(:fork) do |&block|
          expect(RetryingScan).to receive(:run)
          block.call()
        end
        expect(worker).to receive(:close_parent_process_writer)
        worker.run({})
      end

      it 'sets :state to working' do
        worker = ParallelTestBatchWorker.new({ test_batch_results: [], batch_index: 1 })
        allow(Process).to receive(:fork)
        states = [ worker.state ]
        allow(worker).to receive(:state=) { |new_state| states << new_state }
        worker.run({})
        expect(states).to eq(
          %i[ready_to_work working]
        )
      end

      it 'updates :pid when forking' do
        worker = ParallelTestBatchWorker.new({ test_batch_results: [], batch_index: 1 })
        allow(Process).to receive(:fork).and_return(11)
        worker.run({})
        expect(worker.pid).to eq(11)
      end
    end

    describe '#process_results' do
      before(:each) do
        @worker = ParallelTestBatchWorker.new({ test_batch_results: [], batch_index: 2 })
        allow(@worker).to receive(:reroute_stdout_to_logfile)
        allow(@worker).to receive(:exit!)
        allow(@worker).to receive(:start_test_status_monitor)
        logfile = StringIO.new
        @worker.instance_variable_set(:@logfile, logfile)
        
        allow(File).to receive(:foreach).and_yield('')
        reader_writer = StringIO.new
        pipes = [
          reader_writer,
          reader_writer
        ]
        allow(reader_writer).to receive(:close)
        allow(reader_writer).to receive(:gets) do
          reader_writer.string
        end
        allow(IO).to receive(:pipe).and_return(pipes)
      end

      it 'resets :pid when done' do
        allow(Process).to receive(:fork).and_return(11)
        @worker.run({})
        @worker.process_results
        expect(@worker.pid).to be_nil
      end

      it 'updates :test_batch_results with a pass' do
        allow(Process).to receive(:fork) do |&block|          
          allow(RetryingScan).to receive(:run).and_return(true)
          block.call()
        end
        test_batch_results = @worker.instance_variable_get(:@options)[:test_batch_results]
        allow(File).to receive(:foreach)
        @worker.run({})
        @worker.process_results
        expect(test_batch_results.last).to eq(true)
      end

      it 'updates :test_batch_results with a fail' do
        allow(Process).to receive(:fork) do |&block|          
          allow(RetryingScan).to receive(:run).and_return(false)
          block.call()
        end
        test_batch_results = @worker.instance_variable_get(:@options)[:test_batch_results]
        allow(File).to receive(:foreach)
        @worker.run({})
        @worker.process_results
        expect(test_batch_results.last).to eq(false)
      end
    end

    describe '#reroute_stdout_to_logfile' do
      it 'properly sets up STDOUT STDERR to print to the logfile' do
        worker = ParallelTestBatchWorker.new({ test_batch_results: [], batch_index: 5 })
        pipes = [
          OpenStruct.new,
          OpenStruct.new
        ]
        
        allow(IO).to receive(:pipe).and_return(pipes)
        allow(Dir).to receive(:mktmpdir).and_return('path/to/tmpfile')
        worker.open_interprocess_communication
        
        mock_logfile = OpenStruct.new
        expect(File).to receive(:open).with('path/to/tmpfile/parallel-test-batch-6.txt', 'w').and_return(mock_logfile)
        expect(pipes[0]).to receive(:close)

        expect($stdout).to receive(:reopen).with(mock_logfile)
        expect($stderr).to receive(:reopen).with(mock_logfile)
        worker.reroute_stdout_to_logfile
      end

      it 'properly prints out the results when completed' do
        worker = ParallelTestBatchWorker.new({ test_batch_results: [], batch_index: 5 })
        mock_writer = StringIO.new

        mock_logfile = OpenStruct.new
        worker.instance_variable_set(:@logfile, mock_logfile)
        worker.instance_variable_set(:@writer, mock_writer)

        expect(mock_logfile).to receive(:close)
        expect(mock_writer).to receive(:puts).with('false')
        expect(mock_writer).to receive(:close)
        worker.handle_child_process_results(false)
      end
    end

    describe '#read_test_statuses' do
      it 'reads only the current run and its attempt logs' do
        Dir.mktmpdir do |directory|
          old_run = File.join(directory, 'run-old', 'attempt-1')
          current_run = File.join(directory, 'run-current', 'attempt-1')
          FileUtils.mkdir_p([old_run, current_run])
          File.write(File.join(old_run, 'scan.log'), "Test Case '-[BettermeUITests.ExampleUITests testOld]' passed (0.1 seconds).\n")
          File.write(File.join(current_run, 'scan.log'), "Test Case '-[BettermeUITests.ExampleUITests testCurrent]' passed (0.1 seconds).\n")
          worker = ParallelTestBatchWorker.new(buildlog_path: directory, batch_index: 0, test_batch_results: [])
          worker.instance_variable_set(:@monitor_log_path, File.join(directory, 'run-current'))
          output = StringIO.new
          original_stdout = $stdout
          $stdout = output
          begin
            worker.read_test_statuses({})
          ensure
            $stdout = original_stdout
          end
          expect(output.string).to eq("[worker 1] BettermeUITests.ExampleUITests/testCurrent PASSED\n")
        end
      end

      it 'prints only new test events, including events after a log is truncated for a retry' do
        Dir.mktmpdir do |directory|
          worker = ParallelTestBatchWorker.new(buildlog_path: directory, batch_index: 1, test_batch_results: [])
          log_path = File.join(directory, 'Betterme-Acceptance.log')
          offsets = {}
          output = StringIO.new
          original_stdout = $stdout
          $stdout = output
          begin
            File.write(log_path, '')
            worker.read_test_statuses(offsets)
            File.write(log_path, "Technical worker detail\nTest Case '-[BettermeUITests.ExampleUITests testOne]' started (Iteration 1 of 3).\n")
            worker.read_test_statuses(offsets)
            worker.read_test_statuses(offsets)
            File.open(log_path, 'a') { |log| log.puts("Test Case '-[BettermeUITests.ExampleUITests testOne]' passed (1.2 seconds).") }
            worker.read_test_statuses(offsets)
            File.open(log_path, 'a') { |log| log.write("Test Case '-[BettermeUITests.ExampleUITests testPartial]' sta") }
            worker.read_test_statuses(offsets)
            File.open(log_path, 'a') { |log| log.write("rted.\n") }
            worker.read_test_statuses(offsets)
            File.write(log_path, "Test Case '-[BettermeUITests.ExampleUITests testTwo]' failed (0.2 seconds).\n")
            worker.read_test_statuses(offsets)
          ensure
            $stdout = original_stdout
          end

          expect(output.string.lines).to eq([
            "[worker 2] BettermeUITests.ExampleUITests/testOne PASSED\n",
            "[worker 2] BettermeUITests.ExampleUITests/testTwo FAILED\n"
          ])
        end
      end
    end
  end
end
