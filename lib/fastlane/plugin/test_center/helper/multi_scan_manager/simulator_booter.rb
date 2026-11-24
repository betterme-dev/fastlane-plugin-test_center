require 'tempfile'

module TestCenter
  module Helper
    module MultiScanManager
      class SimulatorBooter
        BOOT_TIMEOUT = 300
        SHUTDOWN_TIMEOUT = 30
        MAX_ATTEMPTS = 2

        def self.boot(udid)
          errors = []
          MAX_ATTEMPTS.times do |attempt|
            output, status = run_command(BOOT_TIMEOUT, 'xcrun', 'simctl', 'bootstatus', udid, '-b')
            return if status&.success?

            errors << "attempt #{attempt + 1}: #{output.strip}"
            if attempt + 1 < MAX_ATTEMPTS
              FastlaneCore::UI.important("Simulator #{udid} did not finish booting; retrying")
              shutdown(udid)
            end
          end

          raise "Unable to boot simulator #{udid}: #{errors.join('; ')}"
        end

        def self.shutdown(udid)
          run_command(SHUTDOWN_TIMEOUT, 'xcrun', 'simctl', 'shutdown', udid)
        end

        def self.run_command(timeout, *command)
          Tempfile.create('multi-scan-simulator-boot') do |output|
            pid = Process.spawn(*command, out: output, err: output, pgroup: true)
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

            loop do
              finished_pid, status = Process.waitpid2(pid, Process::WNOHANG)
              if finished_pid
                output.rewind
                return [output.read, status]
              end

              if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
                begin
                  Process.kill('KILL', -pid)
                rescue Errno::ESRCH
                  # The process group exited while the deadline was being handled.
                end
                Process.waitpid(pid)
                output.rewind
                return [output.read + "\nTimed out after #{timeout}s", nil]
              end

              sleep 0.1
            end
          end
        end
      end
    end
  end
end
