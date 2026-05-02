# typed: false
# frozen_string_literal: true

class MicroagentKit < Formula
  desc "Run Linux workspaces inside microVMs"
  homepage "https://github.com/geoffbelknap/microagent-kit"
  url "https://github.com/geoffbelknap/microagent-kit.git",
      tag:      "v0.1.4",
      revision: "6459d6691ae169905cd974ced39330a94063e9ef"

  depends_on "go" => :build
  depends_on xcode: :build
  depends_on "e2fsprogs"

  def install
    system "go", "build",
      "-ldflags", "-s -w -X main.version=#{version}",
      "-o", bin/"microagent",
      "./cmd/microagent"

    with_env(GOOS: "linux", GOARCH: "arm64", CGO_ENABLED: "0") do
      system "go", "build",
        "-ldflags", "-s -w",
        "-o", bin/"microagent-guestinit-arm64",
        "./cmd/microagent-guestinit"
    end

    with_env(GOOS: "linux", GOARCH: "amd64", CGO_ENABLED: "0") do
      system "go", "build",
        "-ldflags", "-s -w",
        "-o", bin/"microagent-guestinit-amd64",
        "./cmd/microagent-guestinit"
    end

    cd "helpers/applevf" do
      system "swift", "build", "--configuration", "release", "--disable-sandbox"
      system "codesign", "-s", "-", "-f",
        "--entitlements", "microagent-applevf-helper.entitlements",
        ".build/release/microagent-applevf-helper"
      bin.install ".build/release/microagent-applevf-helper"
    end
  end

  test do
    assert_match "microagent #{version}", shell_output("#{bin}/microagent version")
    assert_match "image_ref is required", shell_output("#{bin}/microagent rootfs build 2>&1", 1)
    assert_match "microagent kernel", shell_output("#{bin}/microagent kernel help")
    assert_path_exists bin/"microagent-guestinit-arm64"
    assert_path_exists bin/"microagent-guestinit-amd64"

    output = pipe_output("#{bin}/microagent-applevf-helper", '{"command":"host"}', 0)
    assert_match '"ok" : true', output
    assert_match '"backend" : "apple-vf"', output
  end
end
