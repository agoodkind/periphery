#!/usr/bin/env ruby

formula_path, version, sha256 = ARGV
abort "usage: update_homebrew_formula.rb FORMULA VERSION SHA256" unless ARGV.length == 3
abort "invalid SHA256" unless sha256.match?(/\A[0-9a-f]{64}\z/)

release_url = "https://github.com/agoodkind/periphery/releases/download/#{version}/periphery-#{version}-macos-arm64.zip"
formula = File.read(formula_path)
abort "formula URL is missing" unless formula.match?(/^  url ".*"$/)
abort "formula version is missing" unless formula.match?(/^  version ".*"$/)
abort "formula SHA256 is missing" unless formula.match?(/^  sha256 ".*"$/)

formula.sub!(/^  url ".*"$/, "  url \"#{release_url}\"")
formula.sub!(/^  version ".*"$/, "  version \"#{version}\"")
formula.sub!(/^  sha256 ".*"$/, "  sha256 \"#{sha256}\"")
File.write(formula_path, formula)
