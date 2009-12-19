require File.dirname(__FILE__) + "/../spec_helper"

describe Braintree::Http do
  describe "self._handle_response" do
    it "raises an AuthenticationError if authentication fails" do
      begin
        original_key = Braintree::Configuration.public_key
        Braintree::Configuration.public_key = "invalid_public_key"
        expect do
          Braintree::Http.get "/customers"
        end.to raise_error(Braintree::AuthenticationError)
      ensure
        Braintree::Configuration.public_key = original_key
      end
    end

    it "raises an AuthorizationError if authorization fails" do
      expect do
        Braintree::Http.get "/users"
      end.to raise_error(Braintree::AuthorizationError)
    end
  end
  
  describe "self._http_do" do
    it "logs one line of info to the logger" do
      begin
        old_logger = Braintree::Configuration.logger
        now_in_utc = Time.utc(2009, 10, 10, 13, 55, 36)
        SpecHelper.stub_time_dot_now(now_in_utc) do
          output = StringIO.new
          Braintree::Configuration.logger = Logger.new(output)
          Braintree::Configuration.logger.level = Logger::INFO
          Braintree::Customer.all
          utc_or_gmt = Time.now.utc.strftime("%Z")
          output.string.should include("[Braintree] [10/Oct/2009 13:55:36 #{utc_or_gmt}] GET /customers?page=1 200")
        end
      ensure
        Braintree::Configuration.logger = old_logger
      end
    end

    it "logs full request and response for debug logger" do
      customer = Braintree::Customer.create.customer
      begin
        old_logger = Braintree::Configuration.logger
        now_in_utc = Time.utc(2009, 10, 10, 13, 55, 36)
        SpecHelper.stub_time_dot_now(now_in_utc) do
          output = StringIO.new
          Braintree::Configuration.logger = Logger.new(output)
          Braintree::Configuration.logger.level = Logger::DEBUG
          result = Braintree::CreditCard.create(
            :customer_id => customer.id,
            :cardholder_name => "Sam Jones",
            :number => Braintree::Test::CreditCardNumbers::Visa,
            :expiration_date => "05/2009"
          )
          result.success?.should == true
          utc_or_gmt = Time.now.utc.strftime("%Z")
          output.string.should include("[Braintree] [10/Oct/2009 13:55:36 #{utc_or_gmt}] POST /payment_methods")
          output.string.should include("[Braintree]   <cardholder-name>Sam Jones</cardholder-name>")
          output.string.should include("[Braintree]   <number>401288******1881</number>")
          output.string.should include("[Braintree] [10/Oct/2009 13:55:36 #{utc_or_gmt}] 201 Created")
          output.string.should match(/\[Braintree\]   <token>\w+<\/token>/)
        end
      ensure
        Braintree::Configuration.logger = old_logger
      end
    end

    describe "ssl verification" do
      it "rejects when the certificate isn't verified by our certificate authority (self-signed)" do
        begin
          use_ssl = Braintree::Configuration.ssl?
          Braintree::Configuration.stub(:ssl?).and_return(true)
          Braintree::Configuration.stub(:port).and_return(8443)

          start_ssl_server do
            expect { Braintree::Http._http_do(Net::HTTP::Get, "/login") }.to raise_error(Braintree::SSLCertificateError, /Preverify: false, Error: self signed certificate/)
          end
        ensure
          Braintree::Configuration.stub(:ssl?).and_return(use_ssl)
        end
      end

      it "rejets when the certificate is signed by a different (but valid) root CA" do
        # Random CA root file from a different certificate authority
        begin
          original_ca_file = Braintree::Configuration.ca_file
          Braintree::Configuration.stub(:ca_file).and_return(File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "ssl", "geotrust_global.crt")))
          use_ssl = Braintree::Configuration.ssl?
          Braintree::Configuration.stub(:ssl?).and_return(true)
          Braintree::Configuration.stub(:port).and_return(8443)

          start_ssl_server do
            expect { Braintree::Http._http_do(Net::HTTP::Get, "/login") }.to raise_error(Braintree::SSLCertificateError, /Preverify: false, Error: self signed certificate/)
          end
        ensure
          Braintree::Configuration.stub(:ssl?).and_return(use_ssl)
          Braintree::Configuration.stub(:ca_file).and_return(original_ca_file)
        end
      end

      it "accepts the certificate on the QA server" do
        begin
          original_env = Braintree::Configuration.environment
          Braintree::Configuration.environment = :qa
          Braintree::Configuration.stub(:base_merchant_path).and_return("/")

          expect { Braintree::Http._http_do(Net::HTTP::Get, "/login") }.to_not raise_error
        ensure
          Braintree::Configuration.environment = original_env
        end
      end

      it "accepts the certificate on the sandbox server" do
        begin
          original_env = Braintree::Configuration.environment
          Braintree::Configuration.environment = :sandbox
          Braintree::Configuration.stub(:base_merchant_path).and_return("/")

          expect { Braintree::Http._http_do(Net::HTTP::Get, "/login") }.to_not raise_error
        ensure
          Braintree::Configuration.environment = original_env
        end
      end

      xit "Patrick: waiting on a production box - accepts the certificate on the production server" do
        begin
          original_env = Braintree::Configuration.environment
          Braintree::Configuration.environment = :production
          Braintree::Configuration.stub(:base_merchant_path).and_return("/")

          expect { Braintree::Http._http_do(Net::HTTP::Get, "/login") }.to_not raise_error
        ensure
          Braintree::Configuration.environment = original_env
        end
      end

      it "raises an appropriate error if certificate fails validation" do
        begin
          original_env = Braintree::Configuration.environment
          Braintree::Configuration.environment = :qa
          Braintree::Configuration.stub(:base_merchant_path).and_return("/")
          original_ca_file = Braintree::Configuration.ca_file
          Braintree::Configuration.stub(:ca_file).and_return(nil)
          
          expect { Braintree::Http._http_do(Net::HTTP::Get, "/login") }.to raise_error(Braintree::SSLCertificateError)
        ensure
          Braintree::Configuration.environment = original_env
        end
      end
    end
  end

  describe "self._verify_ssl_certificate" do
    it "raises if preverify is false" do
      context = OpenSSL::X509::StoreContext.new(OpenSSL::X509::Store.new)
      expect { Braintree::Http._verify_ssl_certificate(false, context) }.to raise_error(Braintree::SSLCertificateError)
    end

    it "raise if ssl_context doesn't have an error code of 0" do
      context = OpenSSL::X509::StoreContext.new(OpenSSL::X509::Store.new)
      context.error = 19 # ca_file incorrect, self-signed
      expect { Braintree::Http._verify_ssl_certificate(true, context) }.to raise_error(Braintree::SSLCertificateError)
    end

    it "doesn't raise if there is no error" do
      context = OpenSSL::X509::StoreContext.new(OpenSSL::X509::Store.new)
      expect { Braintree::Http._verify_ssl_certificate(true, context) }.to_not raise_error
    end

    it "logs when there is an error" do
      begin
        old_logger = Braintree::Configuration.logger
        output = StringIO.new
        Braintree::Configuration.logger = Logger.new(output)
        utc_or_gmt = Time.now.utc.strftime("%Z")
        context = OpenSSL::X509::StoreContext.new(OpenSSL::X509::Store.new)
        context.error = 19
        expect { Braintree::Http._verify_ssl_certificate(false, context) }.to raise_error(Braintree::SSLCertificateError)
        output.string.should include("SSL Verification failed -- Preverify: false, Error: self signed certificate in certificate chain (19)")
      ensure
        Braintree::Configuration.logger = old_logger
      end
    end

    it "doesn't log when there is not an error" do
      begin
        old_logger = Braintree::Configuration.logger
        output = StringIO.new
        Braintree::Configuration.logger = Logger.new(output)
        utc_or_gmt = Time.now.utc.strftime("%Z")
        context = OpenSSL::X509::StoreContext.new(OpenSSL::X509::Store.new)
        expect { Braintree::Http._verify_ssl_certificate(true, context) }.to_not raise_error(Braintree::SSLCertificateError)
        output.string.should == ""
      ensure
        Braintree::Configuration.logger = old_logger
      end
    end
  end
end
