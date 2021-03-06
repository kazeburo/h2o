use strict;
use warnings;
use Test::More;
use t::Util;

plan skip_all => 'curl not found'
    unless prog_exists('curl');

subtest 'etag' => sub {
    my $fetch = sub {
        my $extra_conf = shift;
        my $server = spawn_h2o(<< "EOT");
hosts:
  default:
    paths:
      /:
        file.dir: examples/doc_root
$extra_conf
EOT
        return `curl --silent --dump-header /dev/stderr http://127.0.0.1:$server->{port}/ 2>&1 > /dev/null`;
    };

    my $etag_re = qr/^etag: /im;
    my $resp = $fetch->('');
    like $resp, $etag_re, "default is on";
    $resp = $fetch->('file.etag: off');
    unlike $resp, $etag_re, "off";
    $resp = $fetch->('file.etag: on');
    like $resp, $etag_re, "on";
};

subtest 'send-gzip' => sub {
    my $doit = sub {
        my ($send_gzip, $curl_opts, $expected_length) = @_;
        my $server = spawn_h2o(<< "EOT");
hosts:
  default:
    paths:
      /:
        file.dir: t/assets/doc_root
@{[ defined $send_gzip ? "file.send-gzip: $send_gzip" : "" ]}
EOT
        my $fetch = sub {
            my $path = shift;
            subtest "send-gzip:@{[ defined $send_gzip ? $send_gzip : q(default) ]}, $curl_opts, $path" => sub {
                my $resp = `curl --silent --dump-header /dev/stderr $curl_opts http://127.0.0.1:$server->{port}$path 2>&1 > /dev/null`;
                like $resp, qr/^content-length:\s*$expected_length\r$/im, "length is as expected";
                if (($send_gzip || '') eq 'ON') {
                    like $resp, qr/^vary:\s*accept-encoding\r$/im, "has vary set";
                } else {
                    unlike $resp, qr/^vary:\s*accept-encoding\r$/im, "not has vary set";
                }
            };
        };
        $fetch->('/index.txt');
        $fetch->('/');
    };

    my $orig_len = (stat 't/assets/doc_root/index.txt')[7];
    my $gz_len = (stat 't/assets/doc_root/index.txt.gz')[7];

    $doit->(undef, "", $orig_len);
    $doit->(undef, q{--header "Accept-Encoding: gzip"}, $orig_len);
    $doit->("OFF", q{--header "Accept-Encoding: gzip"}, $orig_len);

    $doit->("ON", "", $orig_len);
    $doit->("ON", q{--header "Accept-Encoding: gzip"}, $gz_len);
    $doit->("ON", q{--header "Accept-Encoding: gzip, deflate"}, $gz_len);
    $doit->("ON", q{--header "Accept-Encoding: deflate, gzip"}, $gz_len);
    $doit->("ON", q{--header "Accept-Encoding: deflate"}, $orig_len);
};

subtest 'dir-listing' => sub {
    my $server = spawn_h2o(<< 'EOT');
hosts:
  default:
    paths:
      /off:
        file.dir: examples/doc_root
        file.dirlisting: off
      /on:
        file.dir: examples/doc_root
        file.dirlisting: on
    file.index: []
EOT

    my $fetch = sub {
        my $path = shift;
        return `curl --silent --dump-header /dev/stderr http://127.0.0.1:$server->{port}$path 2>&1 > /dev/null`;
    };

    my $resp = $fetch->("/on/");
    like $resp, qr{^HTTP/1\.[0-9]+ 200 }s, "ON returns 200";
    $resp = $fetch->("/off/");
    like $resp, qr{^HTTP/1\.[0-9]+ 403 }s, "OFF returns 403";
};

done_testing();
