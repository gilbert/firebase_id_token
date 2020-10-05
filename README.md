# Ruby Firebase ID Token verifier (pre-release)

![Alt text](https://api.travis-ci.org/fschuindt/firebase_id_token.svg?branch=master)
[![Code Climate](https://codeclimate.com/github/fschuindt/firebase_id_token/badges/gpa.svg)](https://codeclimate.com/github/fschuindt/firebase_id_token)
[![Issue Count](https://codeclimate.com/github/fschuindt/firebase_id_token/badges/issue_count.svg)](https://codeclimate.com/github/fschuindt/firebase_id_token)
[![Test Coverage](https://codeclimate.com/github/fschuindt/firebase_id_token/badges/coverage.svg)](https://codeclimate.com/github/fschuindt/firebase_id_token/coverage)
[![Inline docs](http://inch-ci.org/github/fschuindt/firebase_id_token.svg?branch=master)](http://inch-ci.org/github/fschuindt/firebase_id_token)

A Ruby gem to verify the signature of Firebase ID Tokens. It stores Google's x509 certificates in-memory and manages their expiration time, so you don't need to request Google's API in every execution and can access it as fast as reading from memory.

It also checks the JWT payload parameters as recommended [here](https://firebase.google.com/docs/auth/admin/verify-id-tokens) by Firebase official documentation.

Feel free to open any issue or to [contact me](https://fschuindt.github.io/blog/about/) directly.
Any contribution is welcome.

## Docs

 + http://www.rubydoc.info/gems/firebase_id_token

## Installing

```
gem install firebase_id_token
```

or in your Gemfile
```
gem 'firebase_id_token', '~> 2.4.0'
```
then
```
bundle install
```

## Configuration

It's needed to set up your Firebase Project ID.

If you are using Rails, this should probably go into `config/initializers/firebase_id_token.rb`.
```ruby
FirebaseIdToken.configure do |config|
  config.project_ids = ['your-firebase-project-id']
end
```

`project_ids` must be a Array.

*If you want to verify signatures from more than one Firebase project, just add more Project IDs to the list.*

## Usage

You can get a glimpse of it by reading our RSpec output on your machine. It's
really helpful. But here is a complete guide:

### Downloading Certificates

Before verifying tokens, you need to download Google's x509 certificates.

To do it simply:
```ruby
FirebaseIdToken::Certificates.request
```

It will download the certificates and save it in-memory, but **only** if the certificates cache is empty, or if they have expired. It's recommended to do this before attempting to verify a token. For example:

```ruby
FirebaseIdToken::Certificates.request
firebase_user = FirebaseIdToken::Signature.verify(token_from_request)
=> {"iss"=>"https://securetoken.google.com/firebase-id-token", "name"=>"Bob Test", [...]}
```

This will ensure your certs are present and not expired. It's also thread-safe; if two or more requests simultaneously need to update expired certs, the library only makes one fetch and gracefully handles the others.

To force download and overwrite the cache, use:

```ruby
FirebaseIdToken::Certificates.request!
```

Google give us information about the certificates expiration time, it's used to set a TTL (Time-To-Live) when saving it. By doing so, the library will know when it the certificates need to be updated (but won't automatically – you still need to call `request` yourself!).

#### Certificates Info

Checks the presence of certificates in the cache.
```ruby
FirebaseIdToken::Certificates.present?
=> true
```

How many seconds until the certificate's expiration.
```ruby
FirebaseIdToken::Certificates.ttl
=> 22352
```

Lists all certificates in a database.
```ruby
FirebaseIdToken::Certificates.all
=> [{"ec8f292sd30224afac5c55540df66d1f999d" => <OpenSSL::X509::Certificate: [...]]
```

Finds the respective certificate of a given Key ID.
```ruby
FirebaseIdToken::Certificates.find('ec8f292sd30224afac5c55540df66d1f999d')
=> <OpenSSL::X509::Certificate: subject=<OpenSSL::X509 [...]>
```

### Verifying Tokens

Pass the Firebase ID Token to `FirebaseIdToken::Signature.verify` and it will return the token payload if everything is ok:

```ruby
FirebaseIdToken::Certificates.request
FirebaseIdToken::Signature.verify(token)
=> {"iss"=>"https://securetoken.google.com/firebase-id-token", "name"=>"Bob Test", [...]}
```

When either the signature is false or the token is invalid, it will return `nil`:
```ruby
FirebaseIdToken::Signature.verify(fake_token)
=> nil

FirebaseIdToken::Signature.verify('aaaaaa')
=> nil
```

**WARNING:** If you try to verify a signature without any certificates in the cache, it will raise a `FirebaseIdToken::Exceptions::NoCertificatesError`.

#### Payload Structure

In case you need, here's a example of the payload structure from a Google login in JSON.
```json
{
   "iss":"https://securetoken.google.com/firebase-id-token",
   "name":"Ugly Bob",
   "picture":"https://someurl.com/photo.jpg",
   "aud":"firebase-id-token",
   "auth_time":1492981192,
   "user_id":"theUserID",
   "sub":"theUserID",
   "iat":1492981200,
   "exp":33029000017,
   "email":"uglybob@emailurl.com",
   "email_verified":true,
   "firebase":{
      "identities":{
         "google.com":[
            "1010101010101010101"
         ],
         "email":[
            "uglybob@emailurl.com"
         ]
      },
      "sign_in_provider":"google.com"
   }
}

```


## Development
The test suite can be run with `bundle exec rake rspec`


The test mode is prepared as preparation for the test.

`FirebaseIdToken.test!`


By using test mode, the following methods become available.

```ruby
# RSA PRIVATE KEY
FirebaseIdToken::Testing::Certificates.private_key
# CERTIFICATE
FirebaseIdToken::Testing::Certificates.certificate
```

CERTIFICATE will always return the same value and will not communicate to google.


### Example
#### Rails test

Describe the following in test_helper.rb etc.

* test_helper

```ruby
class ActiveSupport::TestCase
  setup do
    FirebaseIdToken.test!
  end
end
```

* controller_test

```ruby
require 'test_helper'

module Api
  module V1
    module UsersControllerTest < ActionController::TestCase
      setup do
        @routes = Engine.routes
        @user = users(:one)
      end

      def create_token(sub: nil)
        _payload = payload.merge({sub: sub})
        JWT.encode _payload, OpenSSL::PKey::RSA.new(FirebaseIdToken::Testing::Certificates.private_key), 'RS256'
      end

      def payload
        # payload.json
      end

      test 'should success get api v1 users ' do
        get :show, headers: create_token(@user.id)
        assert_response :success
      end
    end
  end
end
```


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
