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

my @results = $awis->crawl(url => "http://use.perl.org");
is(scalar(@results), 10, "Ten results");

foreach my $result (@results) {
  is($result->{url}, "http://use.perl.org:80/", "url");
  is($result->{ip}, "66.35.250.197", "ip");
  isa_ok($result->{date}, 'DateTime', "date");
  is($result->{content_type}, "text/html", "content type is text/html");
  is($result->{code}, 200, "code");
  ok($result->{length} > 30_000, "length > 30_000");
  is($result->{language}, "en.us-ascii", "language is en.us-ascii");

  ok(scalar(@{$result->{other_urls}}) > 3, "> 3 other urls");
  ok(scalar(@{$result->{images}}) > 8, "> 8 images");
  ok(scalar(@{$result->{links}}) > 50, "> 50 links");
};

my @links = $awis->search(query => 'leon brocard', relevance => 4);
foreach my $link (@links) {
  ok($link->{score}, "score");
#  ok($link->{title}, "title");
  ok($link->{uri}, "url");
}
