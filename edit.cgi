#!/usr/local/bin/perl
# Show a form for editing a slave domain's master IPs

require 'virtualmin-slavedns-lib.pl';
&ReadParse();

# Get and check the domain
&can_edit_slave($in{'dom'}) || &error($text{'edit_ecannot'});
$z = &virtual_server::get_bind_zone($in{'dom'});
$z || &error($text{'edit_ezone'});
$d = &virtual_server::get_domain_by("dom", $in{'dom'});
&virtual_server::require_bind();

&ui_print_header(&virtual_server::domain_in($d), $text{'edit_title'}, "");

print &ui_form_start("save.cgi");
print &ui_hidden("dom", $in{'dom'});
print &ui_table_start($text{'edit_header'}, undef, 2, [ "width=30%" ]);

# Master IP addresses
$masters = &bind8::find('masters', $z->{'members'});
@mips = map { $_->{'name'} } @{$masters->{'members'}};
print &ui_table_row($text{'edit_master'},
	&ui_textarea("master", join("\n", @mips), 5, 20));

# Current records
$file = &bind8::find('file', $z->{'members'});
if ($file) {
	@recs = &bind8::read_zone_file(
		&bind8::make_chroot($file->{'values'}->[0]));
	if (@recs) {
		$rtable = &ui_columns_start([ $text{'edit_rname'},
					      $text{'edit_rtype'},
					      $text{'edit_rvalue'} ]);
		foreach $r (grep { $_->{'type'} ne 'SOA' } @recs) {
			$name = $r->{'name'};
			if ($name =~ /^(\S+)\.$in{'dom'}\.$/) {
				$name = $1;
				}
			$type = $bind8::text{'type_'.$r->{'type'}};
			if ($type) {
				$type .= " ($r->{'type'})";
				}
			else {
				$type = $r->{'type'};
				}
			$rtable .= &ui_columns_row([
				$name, $type, join(" ", @{$r->{'values'}})
				]);
			}
		$rtable .= &ui_columns_end();
		print &ui_table_row($text{'edit_recs'}, $rtable);
		}
	else {
		# None yet!
		print &ui_table_row($text{'edit_recs'},
				    "<i>$text{'edit_none'}</i>");
		}
	}

print &ui_table_end();
$zoneinfo = &bind8::get_zone_name($in{'dom'}, 'any');
$canadv = &foreign_available("bind8") &&
	  $zoneinfo &&
	  &bind8::can_edit_zone($zoneinfo);
print &ui_form_end([ [ undef, $text{'save'} ],
		     $canadv ? ( [ 'adv', $text{'edit_adv'} ] ) : ( ) ]);

&ui_print_footer("/", $text{'index'});

