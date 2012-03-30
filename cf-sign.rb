#!/usr/bin/ruby

require 'rubygems'
require 'aws_cf_signer'

# Private key belonging to builds@kartoffl.ly user, because that user
# owns the secure CF distro, which has "self" as a trusted_signer.
#
# Technically this could be a private key belonging to any AWS ID,
# so long as that AWS ID is on the trusted_signer list for the 
# secure CF distro.
trusted_signer_private_key_path = "/Users/gmcnaughton/dev/aws/cloudfront/builds@kartoffl.ly/pk-APKAI4IMTL3P45SPWVQQ.pem"
signer = AwsCfSigner.new(trusted_signer_private_key_path)

raw = "http://ksi2-files-dev.s3.amazonaws.com/beer.mp4"
unsigned = "http://d13tq9a2b5f89g.cloudfront.net/beer.mp4"
signed = signer.sign(unsigned, :ending => Time.now + 3600)

puts "Signed = #{signed}"