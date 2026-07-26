# typed: false
# frozen_string_literal: true

# Latest channel: pinned to the tip of microagent main, bumped automatically
# by microagent's latest.yaml workflow on every merge. Builds from source at
# the pinned revision, same as the stable microagent formula.
class MicroagentLatest < Formula
  desc "Run Linux workspaces inside microVMs (latest build from main)"
  homepage "https://github.com/geoffbelknap/microagent"
  url "https://github.com/geoffbelknap/microagent.git",
      revision: "fc72a7c7699932e50863751b7ee741368941dd4b"
  version "0.8.7-latest.1385"

  depends_on "go" => :build
  depends_on xcode: :build if OS.mac?

  on_macos do
    on_arm do
      resource "apple-vf-kernel" do
        url "https://kernels.microagent.sh/apple-vf/arm64/6.18.37/Image"
        sha256 "850668120d7d1427db2d547c2276151321c296aa661fd917c0ca60fc09af9f8d"
      end
    end
  end

  on_linux do
    depends_on "e2fsprogs"
    # `pasta` (from the `passt` package) backs the default `--network user`
    # mode on Linux Firecracker — unprivileged outbound networking via user
    # namespaces. macOS uses VZNATNetworkDeviceAttachment instead, which is
    # in-framework and needs no external dependency.
    depends_on "passt"

    on_arm do
      resource "firecracker" do
        url "https://github.com/firecracker-microvm/firecracker/releases/download/v1.15.1/firecracker-v1.15.1-aarch64.tgz"
        sha256 "00654ac1e702a22744121ea9f10a4f792ebd7c3a744cba587dfac9fcb79b41a5"
      end
    end

    on_intel do
      resource "firecracker" do
        url "https://github.com/firecracker-microvm/firecracker/releases/download/v1.15.1/firecracker-v1.15.1-x86_64.tgz"
        sha256 "d4a32ab2322d887ca1bc4a4e7afa9cc35393e6362dfc2b3becb389d362e4275a"
      end

      resource "linux-kvm-kernel" do
        url "https://kernels.microagent.sh/linux-kvm/amd64/6.18.36/vmlinux"
        sha256 "02804d951d654f1538dc58d1bccd6a8f702b26ba5c6180531b3dbdb179d18fb6"
      end
    end
  end

  conflicts_with "microagent", because: "both install a `microagent` binary"

  def install
    system "go", "build",
           "-ldflags", "-s -w -X main.version=#{version}",
           "-o", bin/"microagent",
           "./cmd/microagent"

    guest_arch = Hardware::CPU.arm? ? "arm64" : "amd64"
    with_env(GOOS: "linux", GOARCH: guest_arch, CGO_ENABLED: "0") do
      system "go", "build",
             "-ldflags", "-s -w",
             "-o", libexec/"microagent-guestinit-#{guest_arch}",
             "./cmd/microagent-guestinit"
    end

    if OS.mac?
      cd "supervisors/applevf" do
        system "swift", "build", "--configuration", "release", "--disable-sandbox"
        system "codesign", "-s", "-", "-f",
               "--entitlements", "microagent-applevf-supervisor.entitlements",
               ".build/release/microagent-applevf-supervisor"
        bin.install ".build/release/microagent-applevf-supervisor"
        bin.install_symlink bin/"microagent-applevf-supervisor" => "microagent-supervisor"
      end
      if Hardware::CPU.arm?
        resource("apple-vf-kernel").stage do
          (libexec/"kernels/apple-vf/arm64").install "Image" => "Image"
        end
      end
    else
      supervisor_arch = Hardware::CPU.arm? ? "arm64" : "amd64"
      supervisor = bin/"microagent-firecracker-supervisor-#{supervisor_arch}"
      system "go", "build",
             "-ldflags", "-s -w",
             "-o", supervisor,
             "./cmd/microagent-firecracker-supervisor"
      bin.install_symlink supervisor => "microagent-firecracker-supervisor"
      bin.install_symlink supervisor => "microagent-supervisor"

      firecracker_arch = Hardware::CPU.arm? ? "aarch64" : "x86_64"
      resource("firecracker").stage do
        libexec.install "firecracker-v1.15.1-#{firecracker_arch}" => "firecracker"
      end
      if Hardware::CPU.intel? && Hardware::CPU.is_64_bit?
        resource("linux-kvm-kernel").stage do
          (libexec/"kernels/linux-kvm/amd64").install "vmlinux" => "Image"
        end
      end
    end
  end

  def caveats
    <<~EOS
      This is the latest build from main, refreshed on every merge. It
      conflicts with the stable `microagent` formula (both install
      `microagent`).

      Microagent includes its default kernel on supported hosts:
        - macOS arm64: Apple Virtualization Framework kernel
        - Linux x86_64: Firecracker kernel

      Advanced users can replace it with:

        microagent kernel install --from /path/to/Image --sha256 <sha256>

      Networking (Linux): "isolated" and "user" (passt) modes work out of the box.
      The "nat", "bridged", and "named" modes need a one-time privileged step
      (it asks for confirmation, then re-runs itself under sudo):

        microagent host setup-networking

      A "brew upgrade" resets this (file capabilities don't survive a reinstall),
      so re-run it after upgrading. Check readiness any time with:

        microagent doctor
    EOS
  end

  test do
    assert_match "microagent #{version}", shell_output("#{bin}/microagent version")
    assert_match "microagent #{version}", shell_output("#{bin}/microagent -v")
    assert_match "image_ref is required", shell_output("#{bin}/microagent rootfs build 2>&1", 1)
    assert_match "microagent kernel", shell_output("#{bin}/microagent kernel help")
    guest_arch = Hardware::CPU.arm? ? "arm64" : "amd64"
    assert_path_exists libexec/"microagent-guestinit-#{guest_arch}"

    if OS.mac?
      assert_path_exists bin/"microagent-supervisor"
      output = pipe_output(bin/"microagent-applevf-supervisor", '{"command":"host"}', 0)
      assert_match '"ok" : true', output
      assert_match '"backend" : "apple-vf"', output
    else
      supervisor_arch = Hardware::CPU.arm? ? "arm64" : "amd64"
      assert_path_exists bin/"microagent-firecracker-supervisor-#{supervisor_arch}"
      assert_path_exists bin/"microagent-firecracker-supervisor"
      assert_path_exists bin/"microagent-supervisor"
      assert_path_exists libexec/"firecracker"
      assert_match "Firecracker", shell_output("#{libexec}/firecracker --version")
    end
  end
end
