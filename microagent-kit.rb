# typed: false
# frozen_string_literal: true

class MicroagentKit < Formula
  desc "CLI and helper protocol for agent microVMs"
  homepage "https://github.com/geoffbelknap/microagent-kit"
  url "https://github.com/geoffbelknap/microagent-kit.git",
      tag:      "v0.1.0",
      revision: "4a1e73688ce8b8051c700704c7bf0138ea3281da"

  depends_on "go" => :build
  depends_on xcode: :build

  def install
    system "go", "build",
      "-ldflags", "-s -w -X main.version=#{version}",
      "-o", bin/"microagent",
      "./cmd/microagent"

    cd "helpers/applevf" do
      system "swift", "build", "--configuration", "release", "--disable-sandbox"
      bin.install ".build/release/microagent-applevf-helper"
    end
  end

  test do
    assert_match "microagent #{version}", shell_output("#{bin}/microagent version")

    output = pipe_output("#{bin}/microagent-applevf-helper", '{"command":"host"}', 0)
    assert_match '"ok" : true', output
    assert_match '"backend" : "apple-vf"', output
  end
end
