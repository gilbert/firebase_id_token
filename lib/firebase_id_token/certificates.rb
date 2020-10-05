module FirebaseIdToken
  # Manage download and access of Google's x509 certificates. Keeps
  # certificates in thread-safe memory.
  #
  # ## Download & Access Certificates
  #
  # It describes two ways to download it: {.request} and {.request!}.
  # The first will only do something when the certificates cache is empty,
  # the second one will always request a new download to Google's API and
  # override the database with the response.
  #
  # It's important to note that when saving a set of certificates, it will also
  # set an expiration time to match Google's API header `expires`. **After
  # this time went out, it will automatically request new certificates.**
  #
  # *To know how many seconds left until the expiration you can use {.ttl}.*
  #
  # When comes to accessing it, you can either use {.present?} to check if
  # there's any data inside the certificates cache or {.all} to obtain an
  # `Array` of current certificates.
  #
  # @example `.request` will only download once
  #   FirebaseIdToken::Certificates.request # Downloads certificates.
  #   FirebaseIdToken::Certificates.request # Won't do anything.
  #   FirebaseIdToken::Certificates.request # Won't do anything either.
  #
  # @example `.request!` will download always
  #   FirebaseIdToken::Certificates.request # Downloads certificates.
  #   FirebaseIdToken::Certificates.request! # Downloads certificates.
  #   FirebaseIdToken::Certificates.request! # Downloads certificates.
  #
  class Certificates
    # Certificates cached locally (JSON `String` or `nil`).
    attr_reader :local_certs

    @@mutex = Mutex.new
    @@local_certs = {}
    @@local_certs_requested_at = Time.now
    @@local_certs_ttl = 0

    # Google's x509 certificates API URL.
    URL = 'https://www.googleapis.com/robot/v1/metadata/x509/'\
      'securetoken@system.gserviceaccount.com'

    def self.reset
      @@local_certs = {}
      @@local_certs_requested_at = Time.now
      @@local_certs_ttl = 0
    end

    # For testing
    @@request_count = 0
    def self.request_count; @@request_count; end

    # Calls {.request!} only if there are no certificates cache. It will
    # return `nil` otherwise.
    #
    # It will raise {Exceptions::CertificatesRequestError} if the request
    # fails or {Exceptions::CertificatesTtlError} when Google responds with a
    # low TTL, check out {.request!} for more info.
    #
    # @return [nil, Hash]
    # @see Certificates.request!
    def self.request
      new.request
    end

    # Triggers a HTTPS request to Google's x509 certificates API. If it
    # responds with a status `200 OK`, saves the request body locally and
    # returns it as a `Hash`.
    #
    # Otherwise it will raise a {Exceptions::CertificatesRequestError}.
    #
    # This is really rare to happen, but Google may respond with a low TTL
    # certificate. This is a `SecurityError` and will raise a
    # {Exceptions::CertificatesTtlError}. You are mostly like to never face it.
    # @return [Hash]
    def self.request!
      new.request!
    end

    # @deprecated Use only `request!` in favor of Ruby conventions.
    # It will raise a warning. Kept for compatibility.
    # @see Certificates.request!
    def self.request_anyway
      warn 'WARNING: FirebaseIdToken::Certificates.request_anyway is '\
        'deprecated. Use FirebaseIdToken::Certificates.request! instead.'

      new.request!
    end

    # Returns `true` if there's certificates data in the cache, `false` otherwise.
    # @example
    #   FirebaseIdToken::Certificates.present? #=> false
    #   FirebaseIdToken::Certificates.request
    #   FirebaseIdToken::Certificates.present? #=> true
    def self.present?
      ! new.local_certs.empty?
    end

    # Returns an array of hashes, each hash is a single `{key => value}` pair
    # containing the certificate KID `String` as key and a
    # `OpenSSL::X509::Certificate` object of the respective certificate as
    # value. Returns a empty `Array` when there's no certificates data in cache.
    # @return [Array]
    # @example
    #   FirebaseIdToken::Certificates.request
    #   certs = FirebaseIdToken::Certificates.all
    #   certs.first #=> {"1d6d01c7[...]" => #<OpenSSL::X509::Certificate[...]}
    def self.all
      new.local_certs.map { |kid, cert|
        { kid => OpenSSL::X509::Certificate.new(cert) } }
    end

    # Returns a `OpenSSL::X509::Certificate` object of the requested Key ID
    # (KID) if there's one. Returns `nil` otherwise.
    #
    # It will raise a {Exceptions::NoCertificatesError} if the
    # certificates cache is empty.
    # @param [String] kid Key ID
    # @return [nil, OpenSSL::X509::Certificate]
    # @example
    #   FirebaseIdToken::Certificates.request
    #   cert = FirebaseIdToken::Certificates.find "1d6d01f4w7d54c7[...]"
    #   #=> <OpenSSL::X509::Certificate: subject=#<OpenSSL [...]
    def self.find(kid, raise_error: false)
      certs = new.local_certs
      raise Exceptions::NoCertificatesError if certs.empty?

      return OpenSSL::X509::Certificate.new certs[kid] if certs[kid]

      return unless raise_error

      raise Exceptions::CertificateNotFound,
        "Unable to find a certificate with `#{kid}`."
    end

    # Returns a `OpenSSL::X509::Certificate` object of the requested Key ID
    # (KID) if there's one.
    #
    # @raise {Exceptions::CertificateNotFound} if it cannot be found.
    #
    # @raise {Exceptions::NoCertificatesError} if the certificates cache
    # is empty.
    #
    # @param [String] kid Key ID
    # @return [OpenSSL::X509::Certificate]
    # @example
    #   FirebaseIdToken::Certificates.request
    #   cert = FirebaseIdToken::Certificates.find! "1d6d01f4w7d54c7[...]"
    #   #=> <OpenSSL::X509::Certificate: subject=#<OpenSSL [...]
    def self.find!(kid)
      find(kid, raise_error: true)
    end

    # Returns the current certificates TTL (Time-To-Live) in seconds. *Zero
    # meaning no certificates.* It's the same as the certificates expiration
    # time, use it to know when to request again.
    # @return [Fixnum]
    def self.ttl
      ttl = @@local_certs_ttl
      ttl < 0 ? 0 : ttl
    end

    def initialize
      @local_certs = read_certificates
    end

    # @see Certificates.request
    def request
      request! if @local_certs.nil? || @local_certs.empty?
    end

    # @see Certificates.request!
    def request!
      if @@mutex.locked?
        # Another thread is currently updating the certs.
        # We want to wait until it's done,
        # BUT we don't want to make another (redundant) request ourself.
        return @@mutex.synchronize do
          @local_certs = read_certificates
        end
      end

      @@mutex.synchronize do
        @@local_certs_requested_at = Time.now
        @@request_count += 1

        @request = HTTParty.get URL
        code = @request.code
        if code == 200
          save_certificates
        else
          raise Exceptions::CertificatesRequestError.new(code)
        end
      end
    end

    private

    def read_certificates
      Time.now < (@@local_certs_requested_at + @@local_certs_ttl) && @@local_certs || {}
    end

    def save_certificates
      @@local_certs = JSON.parse(@request.body)
      @@local_certs_ttl = ttl
      @local_certs = read_certificates
    end

    def ttl
      cache_control = @request.headers['cache-control']
      ttl = cache_control.match(/max-age=([0-9]+)/).captures.first.to_i

      if ttl > 3600
        ttl
      else
        raise Exceptions::CertificatesTtlError
      end
    end
  end
end
