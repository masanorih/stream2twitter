#!/usr/local/bin/perl

use strict;
use warnings;
use Config::Pit;
use Encode qw( decode _utf8_off );
use File::Temp qw(tempfile);
use MIME::Parser;
use Net::Twitter::Lite;
use POSIX qw(strftime);
use WWW::Twitpic;

=pod

post twitter from sendmail aliases pipe command.

set line like below to your aliases.
yourstream2twittermailaccount: |/some/where/stream2twitter.pl

post to twitpic if a mail has a attachment.

Be aware! this script uses Config::Pit,
and .pit files should be at sendmail user's home directory.
# It is /var/spool/mqueue on FreeBSD

If you do not like Config::Pit, you should write $config directly.
Those variables are required.

    # for twitter
    # consumer key/secret from http://dev.twitter.com/apps/XXXXXX
    consumer_key
    consumer_secret
    # access token/secret from http://dev.twitter.com/apps/XXXXXX/my_token
    access_token
    access_token_secret
    # for twitpic
    username
    password

sendmail の aliases の pipe 起動から twitter に投稿するスクリプト
添付があれば twitpic に投稿

=cut

# output stderr to /var/tmp for debug
#open STDERR, '>', '/var/tmp/stream2twitter.stderr';

my $config = pit_get('stream2twitter');

# get body from mail data
my $parser = MIME::Parser->new;
$parser->output_to_core(1);
my $entity = $parser->parse( \*STDIN );
my $body   = get_body($entity);
logging("body : $body");

# get attachment from mail data if exists
my $attach = get_attach($entity);
if ($attach) {
    my $path = attach2path($attach);
    post2twitpic( $config, $body, $path );
}
else {
    post2twitter( $config, $body );
}

######################################################################

sub get_body {
    my $entity      = shift;
    my $body_entity = $entity->is_multipart ? $entity->parts(0) : $entity;
    my $body_handle = $body_entity->bodyhandle;
    return decode( '7bit-jis', $body_handle->as_string );
}

sub get_attach {
    my $entity = shift;
    if ( $entity->is_multipart ) {
        return $entity->parts(1)->bodyhandle->as_string;
    }
    return;
}

sub attach2path {
    my $str = shift;
    my( $fh, $filename ) = tempfile();
    print $fh $str or logging("failed to write to tempfile");
    close $fh;
    return $filename;
}

sub post2twitter {
    my( $config, $body ) = @_;

    my $t = Net::Twitter::Lite->new(
        consumer_key    => $config->{consumer_key},
        consumer_secret => $config->{consumer_secret},
    );
    $t->access_token( $config->{access_token} );
    $t->access_token_secret( $config->{access_token_secret} );

    # post to twitter
    my $status = $t->update( { status => $body } );
}

sub post2twitpic {
    my( $config, $body, $path ) = @_;
    # drop utf8 flag for HTTP::Message::_utf8_downgrade()
    _utf8_off $body;

    my $twitpic = WWW::Twitpic->new(
        username => $config->{username},
        password => $config->{password},
    );
    # post to twitpic
    my $r = $twitpic->post( $path => $body );

    # $r is a WWW::Twitpic::API::Response
    if ( $r->is_success ) {
        logging( "post2twitter succeed : " . $r->url );
    }
    else {
        logging( "post2twitter failed : " . $r->error );
    }
}

sub logging {
    my $str = shift;
    chomp $str;
    my $time = strftime( "%Y-%m-%d %H:%M:%S", localtime time );
    open my $logfh, '>>', '/var/log/stream2twitter.log'
        or die "failed to open logfile";
    binmode $logfh, ':utf8';
    printf $logfh "%s %s\n", $time, $str;
    close $logfh;
}
