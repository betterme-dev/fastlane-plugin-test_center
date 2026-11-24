require_relative 'simulator_booter'

module FastlaneCore
  class DeviceManager
    class Device
      def clone
        raise 'Can only clone iOS Simulators' unless self.is_simulator
        Device.new(
          name: self.name,
          udid: `xcrun simctl clone #{self.udid} '#{self.name}'`.chomp,
          os_type: self.os_type,
          os_version: self.os_version,
          state: self.state,
          is_simulator: self.is_simulator
        )
      end

      def rename(newname)
        `xcrun simctl rename #{self.udid} '#{newname}'`
        self.name = newname
      end

      def disable_hardware_keyboard
        UI.verbose("Disabling hardware keyboard for #{self.udid}")
        plist_filepath = File.expand_path("~/Library/Preferences/com.apple.iphonesimulator.plist")
        keyboard_pref_key = ":DevicePreferences:#{self.udid}:ConnectHardwareKeyboard"

        command = "/usr/libexec/PlistBuddy -c \"Set #{keyboard_pref_key} false\" #{plist_filepath} 2>/dev/null || "
        command << "/usr/libexec/PlistBuddy -c \"Add #{keyboard_pref_key} bool false\" #{plist_filepath}"

        `#{command}`
      end

      def boot
        return unless is_simulator
        return unless os_type == "iOS"
        UI.message("Waiting for simulator #{self} to finish booting")

        TestCenter::Helper::MultiScanManager::SimulatorBooter.boot(self.udid)

        self.state = 'Booted'
      end

      def shutdown
        return unless is_simulator
        return unless os_type == "iOS"
        return if self.state == 'Shutdown'

        UI.message("Shutting down #{self.udid}")
        TestCenter::Helper::MultiScanManager::SimulatorBooter.shutdown(self.udid)
        self.state = 'Shutdown'
      end
    end
  end
end
