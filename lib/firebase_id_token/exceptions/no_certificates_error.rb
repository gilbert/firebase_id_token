module FirebaseIdToken
  module Exceptions
    # @see FirebaseIdToken::Certificates.find
    class NoCertificatesError < StandardError
      def initialize(message = "There's no certificates in the local cache.")
        super message
      end
    end
  end
end
