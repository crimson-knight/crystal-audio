module CrystalAudio
  # Platform detection helpers
  # Use these macros to guard platform-specific code.
  #
  # Example:
  #   {% if CrystalAudio::MACOS %}
  #     # macOS-only code
  #   {% end %}

  MACOS   = {{ flag?(:darwin) && !flag?(:ios) }}
  IOS     = {{ flag?(:ios) }}
  APPLE   = {{ flag?(:darwin) }}
  ANDROID = {{ flag?(:android) }}

  # macOS version checks at runtime
  module MacOS
    def self.version : {major: Int32, minor: Int32, patch: Int32}
      str = `sw_vers -productVersion`.strip
      parts = str.split('.').map(&.to_i)
      {major: parts[0]? || 0, minor: parts[1]? || 0, patch: parts[2]? || 0}
    end

    def self.version_at_least?(major : Int, minor : Int = 0) : Bool
      v = version
      v[:major] > major || (v[:major] == major && v[:minor] >= minor)
    end

    # macOS 13.0+: SCStream audio capture
    def self.screen_capture_kit? : Bool
      version_at_least?(13)
    end

    # macOS 14.2+: AudioHardwareCreateProcessTap (preferred, no screen recording permission)
    def self.process_tap? : Bool
      version_at_least?(14, 2)
    end
  end
end
