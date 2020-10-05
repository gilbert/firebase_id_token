require 'httparty'
require 'jwt'

require 'firebase_id_token/version'
require 'firebase_id_token/exceptions/no_certificates_error'
require 'firebase_id_token/exceptions/certificates_request_error'
require 'firebase_id_token/exceptions/certificates_ttl_error'
require 'firebase_id_token/exceptions/certificate_not_found'
require 'firebase_id_token/configuration'
require 'firebase_id_token/certificates'
require 'firebase_id_token/signature'

# ## List of available methods
# + {Certificates.request}
# + {Certificates.request!}
# + {Certificates.present?}
# + {Certificates.all}
# + {Certificates.ttl}
# + {Certificates.find}
# + {Signature.verify}
# + {FirebaseIdToken.test!}
# + {Testing::Certificates.private_key}
# + {Testing::Certificates.find}
# + {Testing::Certificates.private_key}
# + {Testing::Certificates.certificate}
#
# ## Configuration
#
# You need to set your Firebase Project ID.
#
# **WARNING:** Your `project_ids` must be a `Array`.
# ```
# FirebaseIdToken.configure do |config|
#   config.project_ids = ['my-project-id', 'another-project-id']
# end
# ```
#
# **Defaults**
# + `project_ids` => `[]`
#
module FirebaseIdToken
  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  # Resets Configuration to defaults.
  def self.reset
    @configuration = Configuration.new
  end

  def self.configure
    yield configuration
  end

  # Method for starting test mode.
  # You can verify with a test certificate or you can use a test private key to verify the token.
  # When using, write it at the beginning of the test.
  # @example
  #  class ActiveSupport::TestCase
  #    setup do
  #      FirebaseIdToken.test!
  #    end
  #  end
  def self.test!
    require 'firebase_id_token/testing/certificates'
    self.configuration.certificates = FirebaseIdToken::Testing::Certificates
  end
end
