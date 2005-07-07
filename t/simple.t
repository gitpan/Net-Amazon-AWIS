#!perl
use strict;
use warnings;
use IO::Prompt;
use Test::More;
use Test::Exception;

my $subscription_id;

eval {
  local $SIG{ALRM} = sub { die "alarm\n" };
  alarm 60;
  $subscription_id = prompt("Please enter an AWS subscription ID for testing: ");
  alarm 0;
};

if ($subscription_id && length($subscription_id) == 20) {
  eval 'use Test::More tests => 133;';
} else {
  eval 'use Test::More plan skip_all => "Need AWS subscription ID for testing, skipping"';
}

use_ok("Net::Amazon::AWIS");

my $awis = Net::Amazon::AWIS->new($subscription_id);
isa_ok($awis, "Net::Amazon::AWIS", "Have an object back");

my $data = $awis->url_info(url => "http://use.perl.org/");

ok(!$data->{adult_content}, "not porn");
is_deeply($data->{categories}, [
 { path => 'Top/Computers/Programming/Languages/Perl', title => 'Languages/Perl' },
 { path => 'Top/Computers/Programming/Languages/Perl/Directories', title => 'Perl/Directories' },
], "categories fine");
is($data->{encoding}, "us-ascii", "encoding is us-ascii");
is($data->{locale}, "en", "locale is en");
ok($data->{median_load_time} > 100, "load time > 100ms");
ok($data->{percentile_load_time} < 100, "percentile");
ok($data->{rank} > 1000, "rank");
ok(scalar(@{$data->{related}}) > 5, "related");

$data = $awis->web_map(url => "http://use.perl.org");
ok(scalar(@{$data->{links_in}}) > 5, "links_in");
ok(scalar(@{$data->{links_out}}) > 5, "links_out");

my @results = $awis->crawl(url => "http://www.cpan.org", count => 10);
cmp_ok(scalar(@results), '==', 10, "At least ten results");

foreach my $result (@results) {
  like($result->{url}, qr{http://(www\.)?cpan\.org:80/}, "url");
  is($result->{ip}, "66.39.76.93", "ip");
  isa_ok($result->{date}, 'DateTime', "date");
  is($result->{content_type}, "text/html", "content type is text/html");
  is($result->{code}, 200, "code");
  cmp_ok($result->{length}, '>', 5_000, "length > 5_000");
  is($result->{language}, "en.us-ascii", "language is en.us-ascii");

  cmp_ok(scalar(@{$result->{other_urls}}), '==', 0, "0 other urls");
  cmp_ok(scalar(@{$result->{images}}), '>=', 2, ">= 2 images");
  cmp_ok(scalar(@{$result->{links}}), '>=', 15, ">= 15 links");
};

my @links = $awis->search(query => 'leon brocard', relevance => 4);
foreach my $link (@links) {
  ok($link->{score}, "score");
#  ok($link->{title}, "title");
  ok($link->{uri}, "url");
}
