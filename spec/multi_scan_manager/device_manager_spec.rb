module FastlaneCore
  describe DeviceManager do
    describe '#clone' do
      it 'makes a clone of a simulator' do
        original = DeviceManager::Device.new(
          name: 'quadriceps',
          udid: 'ABCDEFGHIJK',
          os_type: 'iOS',
          os_version: '10.2',
          state: 'Booted',
          is_simulator: true
        )
        allow(original).to receive(:`)
          .with(/xcrun simctl clone/)
          .and_return('ZXYWV')

        clone = original.clone
        expect(clone).not_to eq(original)
        original_ivars = original.instance_variables
        cloned_ivars = clone.instance_variables
        expect(original_ivars.size).to eq(cloned_ivars.size)
        original_ivars.each do |ivar|
          next if ivar == :@udid

          clone_ivar_value = clone.instance_variable_get(ivar)
          original_ivar_value = original.instance_variable_get(ivar)
          expect(clone_ivar_value).to eq(original_ivar_value)
        end
      end
    end

    describe '#rename' do
      it 'properly renames the simulator' do
        original = DeviceManager::Device.new(
          name: 'quadriceps',
          udid: 'ABCDEFGHIJK',
          os_type: 'iOS',
          os_version: '10.2',
          state: 'Booted',
          is_simulator: true
        )
        expect(original).to receive(:`).with(/xcrun simctl rename ABCDEFGHIJK 'biceps'/)
        original.rename('biceps')
        expect(original.name).to eq('biceps')
      end
    end

    describe '#boot' do
      it 'waits for the simulator to finish booting before marking it booted' do
        original = DeviceManager::Device.new(
          name: 'quadriceps',
          udid: 'ABCDEFGHIJK',
          os_type: 'iOS',
          os_version: '10.2',
          state: 'Shutdown',
          is_simulator: true
        )
        expect(TestCenter::Helper::MultiScanManager::SimulatorBooter).to receive(:boot).with('ABCDEFGHIJK')
        original.boot
        expect(original.state).to eq('Booted')
      end

      it 'keeps the simulator unbooted when bootstatus fails' do
        original = DeviceManager::Device.new(
          name: 'quadriceps',
          udid: 'ABCDEFGHIJK',
          os_type: 'iOS',
          os_version: '10.2',
          state: 'Shutdown',
          is_simulator: true
        )
        allow(TestCenter::Helper::MultiScanManager::SimulatorBooter).to receive(:boot).and_raise('boot failed')

        expect { original.boot }.to raise_error('boot failed')
        expect(original.state).to eq('Shutdown')
      end

      it 'waits even when the cached simulator state is Booted' do
        original = DeviceManager::Device.new(
          name: 'quadriceps',
          udid: 'ABCDEFGHIJK',
          os_type: 'iOS',
          os_version: '10.2',
          state: 'Booted',
          is_simulator: true
        )
        expect(TestCenter::Helper::MultiScanManager::SimulatorBooter).to receive(:boot).with('ABCDEFGHIJK')

        original.boot
      end
    end

    describe '#shutdown' do
      it 'properly shuts down the simulator' do
        original = DeviceManager::Device.new(
          name: 'quadriceps',
          udid: 'ABCDEFGHIJK',
          os_type: 'iOS',
          os_version: '10.2',
          state: 'Booted',
          is_simulator: true
        )
        expect(TestCenter::Helper::MultiScanManager::SimulatorBooter).to receive(:shutdown).with('ABCDEFGHIJK')
        original.shutdown
      end

      it 'dpoes not shut down the simulator if it is already shutdown' do
        original = DeviceManager::Device.new(
          name: 'quadriceps',
          udid: 'ABCDEFGHIJK',
          os_type: 'iOS',
          os_version: '10.2',
          state: 'Shutdown',
          is_simulator: true
        )
        expect(TestCenter::Helper::MultiScanManager::SimulatorBooter).not_to receive(:shutdown)
        original.shutdown
      end
    end
  end
end
