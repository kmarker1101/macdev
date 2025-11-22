# frozen_string_literal: true

class Macdev < Formula
  desc 'Project-isolated development environments on macOS using Homebrew'
  homepage 'https://github.com/kmarker1101/homebrew-macdev'
  url 'https://github.com/kmarker1101/homebrew-macdev/archive/refs/tags/v0.1.0.tar.gz'
  sha256 '' # TODO: Update with actual SHA256 after creating release
  license 'MIT'
  head 'https://github.com/kmarker1101/homebrew-macdev.git', branch: 'main'

  depends_on 'ruby'

  def install
    ENV['GEM_HOME'] = libexec

    # Install dependencies
    system 'bundle', 'config', 'set', '--local', 'without', 'development:test'
    system 'bundle', 'install'

    # Install the gem files
    (libexec / 'lib').install Dir['lib/*']
    (libexec / 'bin').install 'bin/macdev'

    # Create wrapper script that sets up GEM_HOME
    (bin / 'macdev').write_env_script libexec / 'bin/macdev',
                                      GEM_HOME: ENV.fetch('GEM_HOME', nil),
                                      GEM_PATH: "#{ENV.fetch('GEM_HOME',
                                                             nil)}:#{Formula['ruby'].opt_lib}/ruby/gems/3.4.0"

    # Install shell completions
    bash_completion_script = Utils.safe_popen_read(libexec / 'bin/macdev', 'completion', 'bash')
    (bash_completion / 'macdev').write bash_completion_script

    zsh_completion_script = Utils.safe_popen_read(libexec / 'bin/macdev', 'completion', 'zsh')
    (zsh_completion / '_macdev').write zsh_completion_script

    fish_completion_script = Utils.safe_popen_read(libexec / 'bin/macdev', 'completion', 'fish')
    (fish_completion / 'macdev.fish').write fish_completion_script
  end

  test do
    system bin / 'macdev', 'version'
    assert_match "macdev #{version}", shell_output("#{bin}/macdev version")
  end
end
