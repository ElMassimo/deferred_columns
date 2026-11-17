# frozen_string_literal: true

require_relative 'lib/deferred_columns/version'

Gem::Specification.new do |spec|
  spec.name          = 'deferred_columns'
  spec.version       = DeferredColumns::VERSION
  spec.authors       = ['Maximo Mussini']
  spec.email         = ['maximomussini@gmail.com']

  spec.summary       = 'Leave heavy columns out of the default SELECT of your Active Record models.'
  spec.description   = 'deferred_columns leaves the columns you choose out of every query that does not ask for them, ' \
                       'and raises instead of querying when code reads them without opting in.'
  spec.homepage      = 'https://github.com/ElMassimo/deferred_columns'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.1.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files         = Dir.glob('lib/**/*.rb') + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'activerecord', '>= 7.2'
end
