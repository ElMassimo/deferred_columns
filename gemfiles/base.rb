# frozen_string_literal: true

def main_gemfile
  File.read(File.expand_path('../Gemfile', __dir__)).sub('gemspec', 'gemspec path: ".."')
end
