#!/usr/bin/ruby
#
# == Synopsis
#
# cf-download-distribution: Manipulate Amazon Cloudfront Download Distributions
#
# == Usage
#
# cf-download-distribution.rb [OPTIONS] [command] [args]
#
# == Commands
#   list
#       List all Download Distributions
#
#   get [aws_id]
#       Get details about the Download Distribution identified by [aws_id].
#
#   create [bucket]
#       Create new Download Distribution using S3 origin bucket [bucket].  CNAMEs
#       can optionally be specified with multiple --cname options, and a comment can
#       be applied with --comment option
#
#   delete [aws_id] [e_tag]
#       Delete the Download Distribution identified by [aws_id] and [e_tag].  A
#       distribution must first be disabled before it can be deleted.  Use 'get'
#       to retrieve a distribution's e_tag.
#
#   modify [aws_id]
#       Modify attributes on the Download Distribution identified by [aws_id].  Must
#       be used in conjunction with at least one of the following options:
#       --comment, --enabled, --oai, --trusted-signer, --cname
#
#   wait [aws_id]
#       Loop until a Download Distribution specified by [aws_id] enters the 'deployed'
#       state.  You could use this in scripts if you need to know when a 
#       distribution becomes available for use.
#
# == OPTIONS
#  -h, --help:
#     show help
#
#  -c, --cname [cname]:
#     Use this CNAME on the bucket (can be used with 'create' and 'modify' commands).
#     Multiple --cname options can be used.  When used with modify command, will
#     overwrite all existing CNAMEs
#
#  -o, --oai [origin-access-identity]:
#     Use with 'modify' command to set the Origin Access Identity on a Download
#     Distribution.
#
#  -e, --enable:
#     Use with 'modify' command to enable a Download Distribution.
#
#  -d, --disable:
#     Use with 'modify' command to disable a Download Distribution.
#
#  -t, --trusted-signer [aws_account_id | self]:
#     Use with 'modify' command to set trusted signers on a Download Distribution.
#     Can be used multiple times to set multiple signers.  This will overwrite all
#     existing trusted signers.  Use 'self' for [aws_account_id] to refer to the
#     parent account of the Download Distribution.
#
#  -m, --comment ['some descriptive test']:
#     Set 'comment' on the distribution
#
#  -k, --key [AWS_ACCESS_KEY_ID]
#    Amazon AWS ACCESS KEY ID (can also be set in environment variable 'AWS_ACCESS_KEY_ID')
#
#  -s, --seckey [AWS_SECRET_ACCESS_KEY]
#    Amazon AWS SECRET ACCESS KEY (can also be set in environment variable 'AWS_SECRET_ACCESS_KEY')

# joe miller, <joeym@joeym.net>, 10/30/2010

require 'rubygems'
require 'right_aws'
require 'getoptlong'
require 'rdoc/usage'
require 'ap'

opts = GetoptLong.new(
    [ '--help',    '-h', GetoptLong::NO_ARGUMENT ],
    [ '--cname',   '-c', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--oai',     '-o', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--enable',  '-e', GetoptLong::NO_ARGUMENT ],
    [ '--disable', '-d', GetoptLong::NO_ARGUMENT ],
    [ '--trusted-signer', '-t', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--comment', '-m', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--key',     '-k', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--seckey',  '-s', GetoptLong::REQUIRED_ARGUMENT ]
)

key = ENV['AWS_ACCESS_KEY_ID']
seckey = ENV['AWS_SECRET_ACCESS_KEY']

cnames = []
signers = []
oai = nil
enabled = nil
comment = nil

opts.each do |opt, arg|
    case opt
        when '--help'
            RDoc::usage
        when '--cname'
            cnames.push arg
        when '--comment'
            comment = arg
        when '--key'
            key = arg 
        when '--seckey'
            seckey = arg 
        when '--oai'
            oai = arg
        when '--trusted-signer'
            signers.push arg
        when '--enable'
            enabled = true
        when '--disable'
            enabled = false
    end
end

command = ARGV.shift
args    = ARGV

log = Logger.new(STDERR)
log.level = Logger::FATAL

### connect to amazon cloudfront
cf = RightAws::AcfInterface.new(key, seckey, 
                                {:logger => log} )

if command == 'list'
    dists = cf.list_distributions

    dists.each do |dist|
        ap dist, :indent => -2
    end
elsif command == 'get'
    if args.length < 1
        puts "'get' requires 1 arg (try --help)"
        exit 1
    end

    aws_id = args.shift

    begin
        result = cf.get_distribution(aws_id)
        ap result, :indent => -2
    rescue RightAws::AwsError => e
        e.errors.each do |code, msg|
            puts "Error (#{code}): #{msg}"
        end
        exit 1
    end

elsif command == 'delete'
    if args.length < 2
        puts "'delete' requires 2 args (try --help)"
        exit 1
    end

    aws_id = args.shift
    etag   = args.shift

    begin
        result = cf.delete_distribution(aws_id, etag)
    rescue RightAws::AwsError => e
        e.errors.each do |code, msg|
            puts "Error (#{code}): #{msg}"
        end
        exit 1
    end

    if result == true
        puts "Delete successful"
    else
        puts "Delete failed"
    end

elsif command == 'create'
    if args.length < 1
        puts "'create' requires 1 arg (try --help)"
        exit 1
    end

    ## the CF api expects a canonical bucket name for the origin bucket,
    ## eg "mybucket.s3.amazonaws.com".
    bucket = args.shift
    unless bucket =~ /s3\.amazonaws\.com$/
        bucket = bucket + '.s3.amazonaws.com'
    end

    begin
        config = Hash.new
        config[:s3_origin] ||= Hash.new
        config[:comment] = comment             if comment
        config[:trusted_signers] = signers     if signers.length > 0
        config[:cnames] = cnames               if cnames.length > 0
        config[:enabled] = enabled             if enabled != nil
        config[:s3_origin][:dns_name] = bucket if bucket
        config[:s3_origin][:origin_access_identity] = "origin-access-identity/cloudfront/#{oai}" if oai

        result = cf.create_distribution(config)
    rescue RightAws::AwsError => e
        e.errors.each do |code, msg|
            puts "Error (#{code}): #{msg}"
        end
        exit 1
    end

    ## success
    puts
    puts
    puts
    puts
    puts "Success!"
    puts "domain_name:  #{result[:domain_name]}"
    puts "aws_id:       #{result[:aws_id]}"
    exit 0

elsif command == 'modify'
    if args.length < 1
        puts "'create' requires 1 arg (try --help)"
        exit 1
    end

    aws_id = args.shift

    begin
        config = cf.get_distribution_config(aws_id)
        config[:s3_origin] ||= Hash.new

        config[:comment] = comment          if comment
        config[:trusted_signers] = signers  if signers.length > 0
        config[:cnames] = cnames            if cnames.length > 0
        config[:enabled] = enabled          if enabled != nil
#        config[:s3_origin][:dns_name] = bucket if bucket # Can't change bucket name after create?
        config[:s3_origin][:origin_access_identity] = "origin-access-identity/cloudfront/#{oai}" if oai

        result = cf.set_distribution_config(aws_id, config)

    rescue RightAws::AwsError => e
        e.errors.each do |code, msg|
            puts "Error (#{code}): #{msg}"
        end
        exit 1
    end

    if result == true
        puts "Success!"
    else
        puts "Unknown error occurred"
    end

elsif command == 'wait'
    if args.length < 1
        puts "'wait' requires 1 arg (try --help)"
        exit 1
    end

    aws_id = args.shift

    until cf.get_distribution(aws_id)[:status] == 'Deployed'
        puts "Waiting for download distribution #{aws_id} to become 'Deployed' .."
        sleep 5
    end

else
    puts "no command given (try --help)"
    exit 1
end

exit 0

