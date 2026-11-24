module TestCenter::Helper::MultiScanManager
  describe SimulatorBooter do
    it 'restarts and retries a simulator that did not finish booting' do
      failed = double(success?: false)
      succeeded = double(success?: true)
      expect(SimulatorBooter).to receive(:run_command)
        .with(300, 'xcrun', 'simctl', 'bootstatus', 'A00', '-b')
        .ordered.and_return(['first boot failed', failed])
      expect(SimulatorBooter).to receive(:run_command)
        .with(30, 'xcrun', 'simctl', 'shutdown', 'A00')
        .ordered.and_return(['', succeeded])
      expect(SimulatorBooter).to receive(:run_command)
        .with(300, 'xcrun', 'simctl', 'bootstatus', 'A00', '-b')
        .ordered.and_return(['', succeeded])

      SimulatorBooter.boot('A00')
    end

    it 'fails after two unsuccessful boot attempts' do
      allow(SimulatorBooter).to receive(:run_command).and_return(['boot failed', double(success?: false)])

      expect { SimulatorBooter.boot('A00') }.to raise_error(/A00: attempt 1: boot failed; attempt 2: boot failed/)
      expect(SimulatorBooter).to have_received(:run_command).exactly(3).times
    end

    it 'stops a command when its deadline expires' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output, status = SimulatorBooter.run_command(
        0.1,
        RbConfig.ruby,
        '-e',
        'fork { trap("TERM") {}; sleep 10 }; sleep 10'
      )
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(status).to be_nil
      expect(output).to include('Timed out after 0.1s')
      expect(elapsed).to be < 2
    end
  end
end
