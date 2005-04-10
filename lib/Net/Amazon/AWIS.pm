package Net::Amazon::AWIS;
use strict;
use DateTime::Format::Strptime;
use LWP::UserAgent;
use URI;
use URI::QueryParam;
use XML::LibXML;
use XML::LibXML::XPathContext;
our $VERSION = "0.30";
use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(libxml subscription_id ua));

sub new {
  my($class, $subscription_id) = @_;
  my $self = {};
  bless $self, $class;

  my $ua = LWP::UserAgent->new;
  $ua->timeout(30);
  $self->ua($ua);
  $self->libxml(XML::LibXML->new);
  $self->subscription_id($subscription_id);
  return $self;
}

sub url_info {
  my($self, %options) = @_;

  my $parms = {
    Operation => 'UrlInfo',
    Url => $options{url},
    ResponseGroup => 'AdultContent,Categories,Language,Rank,Related,Speed',
  };

  my $xpc = $self->_request($parms);

  my @categories;
  foreach my $node ($xpc->findnodes("//awis:CategoryData")) {
    my $title = $xpc->findvalue(".//awis:Title", $node);
    my $path  = $xpc->findvalue(".//awis:AbsolutePath", $node);
    push @categories, {
      title => $title,
      path => $path,
    };
  };

  my @related;
  foreach my $node ($xpc->findnodes("//awis:RelatedLink")) {
    push @related, {
      canonical => $xpc->findvalue(".//awis:DataUrl", $node),
      url => $xpc->findvalue(".//awis:NavigableUrl", $node),
      relevance => $xpc->findvalue(".//awis:Relevance", $node),
      title => $xpc->findvalue(".//awis:Title", $node),
    };
  }

  my $data = {
    adult_content =>
      $xpc->findvalue(".//awis:Alexa/awis:ContentData/awis:AdultContent") eq 'yes', 
    categories => \@categories,
    encoding => $xpc->findvalue(".//awis:Alexa/awis:ContentData/awis:Language/awis:Encoding"),
    locale => $xpc->findvalue(".//awis:Alexa/awis:ContentData/awis:Language/awis:Locale"),
    median_load_time => $xpc->findvalue(".//awis:Alexa/awis:ContentData/awis:Speed/awis:MedianLoadTime"),
    percentile_load_time => $xpc->findvalue(".//awis:Alexa/awis:ContentData/awis:Speed/awis:Percentile"),
    rank => $xpc->findvalue(".//awis:Alexa/awis:TrafficData/awis:Rank"),
    related => \@related,
  };
  return $data;
}

sub web_map {
  my($self, %options) = @_;

  my $parms = {
    Operation => 'WebMap',
    Url => $options{url},
    ResponseGroup => 'LinksIn,LinksOut',
    Count => $options{count} || 100,
    Start => $options{start} || 0,
  };

  my $xpc = $self->_request($parms);

  my @in;
  foreach my $node ($xpc->findnodes("//awis:LinksPointingIn/awis:Results/awis:Result")) {
    my $url = $xpc->findvalue(".//awis:DataUrl", $node);
    push @in, $url;
  };
  my @out;
  foreach my $node ($xpc->findnodes("//awis:LinksPointingOut/awis:Results/awis:Result")) {
    my $url = $xpc->findvalue(".//awis:DataUrl", $node);
    push @out, $url;
  };

  return {
    links_in  => \@in,
    links_out => \@out,
  };
}

sub crawl {
  my($self, %options) = @_;

  my $parms = {
    Operation => 'Crawl',
    Url => $options{url},
    ResponseGroup => 'MetaData',
  };

  my $xpc = $self->_request($parms);

  my $format = new DateTime::Format::Strptime(
    pattern     => '%Y%m%d%H%M%S',
  );

  my @results;
  foreach my $node ($xpc->findnodes("//awis:MetaData")) {
    my @other_urls;
    foreach my $subnode ($xpc->findnodes(".//awis:OtherUrl", $node)) {
      push @other_urls, 'http://' . $subnode->textContent;
    }
    my @images;
    foreach my $subnode ($xpc->findnodes(".//awis:Image", $node)) {
      push @images, 'http://' . $subnode->textContent;
    }
    my @links;
    foreach my $subnode ($xpc->findnodes(".//awis:Link", $node)) {
      push @links, {
	name => $xpc->findvalue(".//awis:Name", $subnode),
	uri => 'http://' . $xpc->findvalue(".//awis:LocationURI", $subnode),
      };
    }

    my $result = {
      url => $xpc->findvalue(".//awis:RequestInfo/awis:OriginalRequest", $node),
      ip => $xpc->findvalue(".//awis:RequestInfo/awis:IPAddress", $node),
      date => $format->parse_datetime($xpc->findvalue(".//awis:RequestInfo/awis:RequestDate", $node)),
      content_type => $xpc->findvalue(".//awis:RequestInfo/awis:ContentType", $node),
      code => $xpc->findvalue(".//awis:RequestInfo/awis:ResponseCode", $node),
      length => $xpc->findvalue(".//awis:RequestInfo/awis:Length", $node),
      language => (split(' ', $xpc->findvalue(".//awis:RequestInfo/awis:Language", $node)))[0],
      images => \@images,
      other_urls => \@other_urls,
      links => \@links,
    };
    push @results, $result;
  }
  return @results;
}

sub search {
  my($self, %options) = @_;

  my $parms = {
    Operation => 'Search',
    Query => $options{query},
    ResponseGroup => 'Web',
  };

  $parms->{TimeOut} = $options{timeout} if $options{timeout};
  $parms->{MaxResultsPerHost} = $options{max_results_per_host} if $options{max_results_per_host};
  $parms->{DuplicateCheck} = $options{duplicate_check} if $options{duplicate_check};
  $parms->{CountOnly} = $options{count_only} if $options{count_only};
  $parms->{Context} = $options{context} if $options{context};
  $parms->{Relevance} = $options{relevance} if $options{relevance};
  $parms->{IgnoreWords} = $options{ignore_words} if $options{ignore_words};
  $parms->{Start} = $options{start} if $options{start};
  $parms->{Count} = $options{count} if $options{count};
  $parms->{AdultFilter} = $options{adult_filter} if $options{adult_filter};

  my $xpc = $self->_request($parms);

  my @links;
  foreach my $node ($xpc->findnodes(".//awis:Result")) {
    push @links, {
      title => $xpc->findvalue(".//awis:Title", $node),
      uri => 'http://' . $xpc->findvalue(".//awis:DataUrl", $node),
      score => $xpc->findvalue(".//awis:Score", $node),
    };
  }
  return @links;
}

sub _request {
  my($self, $parms) = @_;
#  sleep 1;

  $parms->{SubscriptionId} = $self->subscription_id;

  my $url = "http://aws-beta.amazon.com/onca/xml?Service=AlexaWebInfoService";

  my $uri = URI->new($url);
  $uri->query_param($_, $parms->{$_}) foreach keys %$parms;
  my $response = $self->ua->get("$uri");

#  die $uri;

  die "Error fetching response: " . $response->status_line unless $response->is_success;

  my $xml = $response->content;
  my $doc = $self->libxml->parse_string($xml);

  my $xpc = XML::LibXML::XPathContext->new($doc);
  $xpc->registerNs('awis', 'http://webservices.amazon.com/AWSAlexa/2004-09-15');

#  warn $doc->toString(1);

  if ($xpc->findnodes("//awis:Error")) {
    die $xpc->findvalue("//awis:Error/awis:Code") . ": " .
      $xpc->findvalue("//awis:Error/awis:Message");
  }

  return $xpc;
}

1;

__END__

=head1 NAME

Net::Amazon::AWIS - Use the Amazon Alexa Web Information Service

=head1 SYNOPSIS

  use Net::Amazon::AWIS;
  my $awis = Net::Amazon::AWIS->new($subscription_id);
  my $data1= $awis->url_info(url => "http://use.perl.org/");
  my $data2 = $awis->web_map(url => "http://use.perl.org");
  my @results = $awis->crawl(url => "http://use.perl.org");

=head1 DESCRIPTION

The Net::Amazon::AWIS module allows you to use the Amazon
Alexa Web Information Service.

The Alexa Web Information Service (AWIS) provides developers with
programmatic access to the information Alexa Internet (www.alexa.com)
collects from its Web Crawl, which currently encompasses more than 100
terabytes of data from over 4 billion Web pages. Developers and Web
site owners can use AWIS as a platform for finding answers to
difficult and interesting problems on the Web, and incorporating them
into their Web applications.

In order to access the Alexa Web Information Service, you will need an
Amazon Web Services Subscription ID. See
http://www.amazon.com/gp/aws/landing.html

Registered developers have free access to the Alexa Web Information
Service during its beta period, but it is limited to 10,000
requests per subscription ID per day.

There are some limitations, so be sure to read the The Amazon Alexa
Web Information Service FAQ.

=head1 INTERFACE

The interface follows. Most of this documentation was copied from the
API reference. Upon errors, an exception is thrown.

=head2 new

The constructor method creates a new Net::Amazon::AWIS
object. You must pass in an Amazon Web Services Subscription ID. See
http://www.amazon.com/gp/aws/landing.html:

  my $sq = Net::Amazon::AWIS->new($subscription_id);

=head2 url_info

The url_info method provides information about URLs. Examples of this
information includes data on how popular a site is, and sites that
are related.

You pass in a URL and get back a hash full of information. This
includes the Alexa three month average traffic rank for the given
site, the median load time and percent of known sites that are slower,
whether the site is likely to contain adult content, the content
language code and character-encoding, which dmoz.org categories the
site is in, and related sites:

  my $data = $awis->url_info(url => "http://use.perl.org/");
  print "Rank:       " . $data->{rank}                 . "\n";
  print "Load time:  " . $data->{median_load_time}     . "\n";
  print "%Load time: " . $data->{percentile_load_time} . "\n";
  print "Likely to contain adult content\n" if $data->{adult_content};
  print "Encoding:   " . $data->{encoding}             . "\n";
  print "Locale:     " . $data->{locale}               . "\n";

  foreach my $cat (@{$data->{categories}}) {
    my $path  = $cat->{path};
    my $title = $cat->{title};
    print "dmoz.org: $path / $title\n";
  }

  foreach my $related (@{$data->{related}}) {
    my $canonical  = $related->{canonical};
    my $url        = $related->{url};
    my $relevance  = $related->{relevance};
    my $title      = $related->{title};
    print "Related: $url / $title ($relevance)\n";
  }

=head2 web_map

The web_map method provides complete listing of all known links
pointing in and links pointing out for any page/URL on the web. Web
Maps have been found to be useful when creating new search engine
algorithms. As of October 2004, there are 17 billion nodes in the web
map, based on 4 million text/html pages crawled. For the 4 billion
URLs crawled, Amazon will be able to provide both links pointing in
and links pointing out information. For the remaining 13 billion URLs,
Amazon will only be able to provide links pointing in.

  my $data = $awis->web_map(url => "http://use.perl.org");
  my @links_in  = $data->{links_in};
  my @links_out = $data->{links_out};

=head2 crawl

The crawl method returns information about a specific URL as provided
by the most recent Alexa Web Crawls. Information about the last few
times the site URL was crawled is returned.

Information per crawl include: URL, IP address, date of the crawl (as
a DateTime object), status code, page length, content type and language.
In addition, a list of other URLs is included (like "rel" URLs), as is
the list of images and links found.

  my @results = $awis->crawl(url => "http://use.perl.org");
  foreach my $result (@results) {
    print "URL: "          . $result->{url} . "\n";
    print "IP: "           . $result->{ip} . "\n";
    print "Date: "         . $result->{date} . "\n";
    print "Code: "         . $result->{code} . "\n";
    print "Length: "       . $result->{length} . "\n";
    print "Content type: " . $result->{content_type} . "\n";
    print "Language: "     . $result->{language} . "\n";

    foreach my $url (@{$result->{other_urls})) {
      print "Other URL: $url\n";
    }

    foreach my $images (@{$result->{images})) {
      print "Image: $image\n";
    }

    foreach my $link (@{$result->{links})) {
      my $name = $link->{name};
      my $uri  = $link->{uri};
      print "Link: $name -> $uri\n";
    }
  }

=head2 search

The search method may be used to retrieve a list of search results
that match one or more keywords. The Web Search is based on an Alexa
index of the web that, as of August 2004, has over 4 billion
URLs. Options are as follows:

timeout: Time in milliseconds to wait for a response. to wait for a
response. Web Search will attempt to respond with as many results as
possible within the timeout period. '0' means inifinite. Default value
is '3000'.

max_results_per_host: Maximum number of results to return from any one
site. '0' means no limit. Default value is '5.'

duplicate_check: set to 'yes' to filter out results that are
substantially similar to those already shown. Default value is 'yes'.

count_only: setting to 'yes' will return only a count of matching
sites. Default value is 'no.'

context: setting to 'yes' will return a Context node beneath each
Result, indicating where keyword(s) match within the document. Default
value is 'yes.'

relevance: allows faster searching with weak relevance (0) to slow
searching with strong relevance checking (4). Default value is '0.'

ignore_words: query terms appearing in nore than this percent of all pages in our
index will be ignored.

start: number of result at which to start. Used for paging through
results. Default value is '0.'

count: number of results (maximum) per page to return. Note that the
response document may contain fewer results than this maximum. Default
value is '10' (maximum 1000).

adult_filter: filter for adult content. 'Yes' will provide strict filtering of
results, showing only sites that are explicitly identified as not
adult. 'Moderate' will filter sitse that are identified as adult, but
allow unknowns to be included. Default value is 'no.'

Note: the results from this search seem to be less accurate than other
web search engines.

  my @links = $awis->search(query => 'leon brocard');
  foreach my $link (@links) {
    my $score = $link->{score};
    my $uri   = $link->{uri};
    my $title = $link->{title} || "No title";
    print "$uri $title ($score)\n";
  }

=head1 BUGS AND LIMITATIONS                                                     
                                                                                
No bugs have been reported. This module currently does not support "Category" searches.
                                                                                
Please report any bugs or feature requests to                                   
C<bug-<Net-Amazon-AWIS>@rt.cpan.org>, or through the web interface at                   
L<http://rt.cpan.org>.  

=head1 AUTHOR

Leon Brocard C<acme@astray.com>

=head1 LICENCE AND COPYRIGHT                                                    
                                                                                
Copyright (c) 2005, Leon Brocard C<acme@astray.com>. All rights reserved.           
                                                                                
This module is free software; you can redistribute it and/or                    
modify it under the same terms as Perl itself.                                  
                                                                                
=head1 DISCLAIMER OF WARRANTY                                                   

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY          
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN        
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES          
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER               
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED                
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE  
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH           
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL            
NECESSARY SERVICING, REPAIR, OR CORRECTION.                                     
                                                                                
IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING           
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR             
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE                 
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,          
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE             
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING           
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A            
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF            
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF               
SUCH DAMAGES.
