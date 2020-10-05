require 'spec_helper'

module FirebaseIdToken
  describe Certificates do
    let (:certs) { File.read('spec/fixtures/files/certificates.json') }
    let (:cache) { 'public, max-age=19302, must-revalidate, no-transform' }
    let (:low_cache) { 'public, max-age=2160, must-revalidate, no-transform' }
    let (:kid) { JSON.parse(certs).first[0] }
    let (:expires_in) { (DateTime.now + (5/24r)).to_s }
    let (:response) { double }

    let (:mock_response) {
      allow(response).to receive(:code) { 200 }
      allow(response).to receive(:headers) { { 'cache-control' => cache } }
      allow(response).to receive(:body) { certs }
    }

    let(:mock_request) {
      mock_response
      allow(HTTParty).to receive(:get).
        with(an_instance_of(String)) { response }
    }

    before :each do
      described_class.reset
      mock_request
    end

    describe '#request' do
      it 'requests certificates when local cache is empty' do
        expect(HTTParty).to receive(:get).
          with(FirebaseIdToken::Certificates::URL)
        described_class.request
      end

      it 'does not requests certificates when local cache is written' do
        expect(HTTParty).to receive(:get).
          with(FirebaseIdToken::Certificates::URL).once
        2.times { described_class.request }
      end
    end

    describe '#request!' do
      it 'always requests certificates' do
        expect(HTTParty).to receive(:get).
          with(FirebaseIdToken::Certificates::URL).twice
        2.times { described_class.request! }
      end

      it 'sets the certificate expiration time' do
        described_class.request!
        ttl = FirebaseIdToken::Certificates.ttl
        expect(ttl).to be(19302)
      end

      it 'raises a error when certificates expires in less than 1 hour' do
        allow(response).to receive(:headers) {{'cache-control' => low_cache}}
        expect{ described_class.request! }.
          to raise_error(Exceptions::CertificatesTtlError)
      end

      it 'raises a error when HTTP response code is other than 200' do
        allow(response).to receive(:code) { 401 }
        expect{ described_class.request! }.
          to raise_error(Exceptions::CertificatesRequestError)
      end
    end

    describe '#request_anyway' do
      it 'also requests certificates' do
        expect(HTTParty).to receive(:get).
          with(FirebaseIdToken::Certificates::URL)

        described_class.request_anyway
      end
    end

    describe '.present?' do
      it 'returns false when local cache is empty' do
        expect(described_class.present?).to be(false)
      end

      it 'returns true when local cache is written' do
        described_class.request
        expect(described_class.present?).to be(true)
      end
    end

    describe '.all' do
      context 'before requesting certificates' do
        it 'returns a empty Array' do
          expect(described_class.all).to eq([])
        end
      end

      context 'after requesting certificates' do
        it 'returns a array of hashes: String keys' do
          described_class.request
          expect(described_class.all.first.keys[0]).to be_a(String)
        end

        it 'returns a array of hashes: OpenSSL::X509::Certificate values' do
          described_class.request
          expect(described_class.all.first.values[0]).
            to be_a(OpenSSL::X509::Certificate)
        end
      end
    end

    describe '.find' do
      context 'without certificates in local cache' do
        it 'raises a exception' do
          expect{ described_class.find(kid)}.
            to raise_error(Exceptions::NoCertificatesError)
        end
      end

      context 'with certificates in local cache' do
        it 'returns a OpenSSL::X509::Certificate when it finds the kid' do
          described_class.request
          expect(described_class.find(kid)).to be_a(OpenSSL::X509::Certificate)
        end

        it 'returns nil when it can not find the kid' do
          described_class.request
          expect(described_class.find('')).to be(nil)
        end
      end
    end

    describe '.find!' do
      context 'without certificates in local cache' do
        it 'raises a exception' do
          expect{ described_class.find!(kid)}.
            to raise_error(Exceptions::NoCertificatesError)
        end
      end
      context 'with certificates in local cache' do
        it 'returns a OpenSSL::X509::Certificate when it finds the kid' do
          described_class.request
          expect(described_class.find!(kid)).to be_a(OpenSSL::X509::Certificate)
        end

        it 'raises a CertificateNotFound error when it can not find the kid' do
          described_class.request
          expect { described_class.find!('') }
            .to raise_error(Exceptions::CertificateNotFound, /Unable to find/)
        end
      end

    end

    describe '.ttl' do
      it 'returns a positive number when has certificates cached' do
        expect(HTTParty).to receive(:get).with(FirebaseIdToken::Certificates::URL).once
        described_class.request
        expect(described_class.ttl).to be > 0
      end

      it 'expiration allows another request' do
        expect(HTTParty).to receive(:get).with(FirebaseIdToken::Certificates::URL).twice
        described_class.request
        expect(described_class.new.local_certs.empty?).to eq(false)

        Timecop.travel(Time.now + described_class.ttl + 1) do
          described_class.request
          expect(described_class.new.local_certs.empty?).to eq(false)
          described_class.request
          expect(described_class.new.local_certs.empty?).to eq(false)
        end
      end

      it 'returns zero when has no certificates cached' do
        expect(described_class.ttl).to eq(0)
      end
    end

    describe 'memory safety' do
      before do
        if Thread.respond_to?(:report_on_exception)
          @report_on_exception_value = Thread.report_on_exception
          Thread.report_on_exception = false
        end

        described_class.reset
      end

      def request_threaded(nthreads)
        threads = []

        nthreads.times do
          threads << Thread.new do
            described_class.request!
          end
        end
        threads.map(&:join)
      end

      it "only makes one request per batch" do
        allow(HTTParty).to receive(:get).with(an_instance_of(String)) do
          sleep 0.2
          response
        end

        orig_count = described_class.request_count

        t = Time.now
        expect { request_threaded(100) }.to_not raise_error
        expect(Time.now).to be > (t + 0.2)
        expect(Time.now).to be < (t + 0.3)

        expect(described_class.request_count).to eq(orig_count + 1)
      end

      after do
        if Thread.respond_to?(:report_on_exception)
          Thread.report_on_exception = @report_on_exception_value
        end
      end
    end

  end
end
