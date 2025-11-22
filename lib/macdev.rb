# frozen_string_literal: true

require 'optparse'
require 'fileutils'
require 'toml-rb'

require_relative 'macdev/version'
require_relative 'macdev/homebrew'
require_relative 'macdev/manifest'
require_relative 'macdev/lock'
require_relative 'macdev/completion'
require_relative 'macdev/environment'
require_relative 'macdev/cli'
