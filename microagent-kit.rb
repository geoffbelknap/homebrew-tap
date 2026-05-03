# typed: false
# frozen_string_literal: true

class MicroagentKit < Formula
  desc "Run Linux workspaces inside microVMs"
  homepage "https://github.com/geoffbelknap/microagent-kit"
  url "https://github.com/geoffbelknap/microagent-kit.git",
      tag:      "v0.1.31",
      revision: "5f1f579dc83b0da82b9fba06ead4f753d48e700f"

  depends_on "go" => :build
  depends_on xcode: :build if OS.mac?
  depends_on "e2fsprogs"

  on_macos do
    on_arm do
      resource "apple-vf-kernel" do
        url "https://github.com/geoffbelknap/microagent-kit/releases/download/kernels-6.12.22-r1/microagent-kernel-6.12.22-apple-vf-arm64"
        sha256 "73fe78e51a8ce348e69311d376a02114440eee6b60bf2e91af54bdf2dfb405ec"
      end
    end
  end

  on_linux do
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

      resource "firecracker-kernel" do
        url "https://github.com/geoffbelknap/microagent-kernels/releases/download/kernels-6.1.155-r2/microagent-kernel-6.1.155-firecracker-amd64"
        sha256 "4bbe8b2fd19f78fea4bf02d52a67482227a896c90a63f272b6a084fa46a416c0"
      end
    end
  end

  def install
    system "go", "build",
           "-ldflags", "-s -w -X main.version=#{version}",
           "-o", bin/"microagent",
           "./cmd/microagent"

    with_env(GOOS: "linux", GOARCH: "arm64", CGO_ENABLED: "0") do
      system "go", "build",
             "-ldflags", "-s -w",
             "-o", libexec/"microagent-guestinit-arm64",
             "./cmd/microagent-guestinit"
    end

    with_env(GOOS: "linux", GOARCH: "amd64", CGO_ENABLED: "0") do
      system "go", "build",
             "-ldflags", "-s -w",
             "-o", libexec/"microagent-guestinit-amd64",
             "./cmd/microagent-guestinit"
    end

    if OS.mac?
      cd "supervisors/applevf" do
        system "swift", "build", "--configuration", "release", "--disable-sandbox"
        system "codesign", "-s", "-", "-f",
               "--entitlements", "microagent-applevf-supervisor.entitlements",
               ".build/release/microagent-applevf-supervisor"
        bin.install ".build/release/microagent-applevf-supervisor"
      end
      if Hardware::CPU.arm?
        resource("apple-vf-kernel").stage do
          (libexec/"kernels/apple-vf/arm64").install "microagent-kernel-6.12.22-apple-vf-arm64" => "Image"
        end
      end
    else
      firecracker_arch = Hardware::CPU.arm? ? "aarch64" : "x86_64"
      resource("firecracker").stage do
        libexec.install "firecracker-v1.15.1-#{firecracker_arch}" => "firecracker"
      end
      if Hardware::CPU.intel? && Hardware::CPU.is_64_bit?
        resource("firecracker-kernel").stage do
          (libexec/"kernels/firecracker/amd64").install "microagent-kernel-6.1.155-firecracker-amd64" => "Image"
        end
      end
    end
  end

  def caveats
    <<~EOS
      Microagent includes its default kernel on supported hosts:
        - macOS arm64: Apple Virtualization Framework kernel
        - Linux x86_64: Firecracker kernel

      Advanced users can replace it with:

        microagent kernel install --from /path/to/Image --sha256 <sha256>
    EOS
  end

  test do
    assert_match "microagent #{version}", shell_output("#{bin}/microagent version")
    assert_match "microagent #{version}", shell_output("#{bin}/microagent -v")
    assert_match "image_ref is required", shell_output("#{bin}/microagent rootfs build 2>&1", 1)
    assert_match "microagent kernel", shell_output("#{bin}/microagent kernel help")
    assert_path_exists libexec/"microagent-guestinit-arm64"
    assert_path_exists libexec/"microagent-guestinit-amd64"

    if OS.mac?
      output = pipe_output("#{bin}/microagent-applevf-supervisor", '{"command":"host"}', 0)
      assert_match '"ok" : true', output
      assert_match '"backend" : "apple-vf"', output
    else
      assert_path_exists libexec/"firecracker"
      assert_match "Firecracker", shell_output("#{libexec}/firecracker --version")
    end
  end
end
