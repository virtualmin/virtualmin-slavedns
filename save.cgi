#!/usr/local/bin/perl
# Update master server IPs

require 'virtualmin-slavedns-lib.pl';
&ReadParse();
&error_setup($text{'save_err'});

if ($in{'adv'}) {
	# Redirect to BIND module
	&redirect("../bind8/edit_slave.cgi?zone=$in{'dom'}");
	return;
	}

# Get and check the domain
&can_edit_slave($in{'dom'}) || &error($text{'edit_ecannot'});
$z = &virtual_server::get_bind_zone($in{'dom'});
$z || &error($text{'edit_ezone'});
$d = &virtual_server::get_domain_by("dom", $in{'dom'});
&virtual_server::require_bind();

# Validate inputs
@mips = split(/\s+/, $in{'master'});
foreach $ip (@mips) {
	&check_ipaddress($ip) || &error(&text('save_emip', $ip));
	}
@mips || &error($text{'save_emips'});

&ui_print_unbuffered_header(&virtual_server::domain_in($d),
			    $text{'edit_title'}, "");

# Update the .conf file
&$virtual_server::first_print($text{'save_doing'});
$masters = &bind8::find('masters', $z->{'members'});
$oldmasters = { %$masters };
$masters->{'members'} = [ map { { 'name' => $_ } } @mips ];
&bind8::save_directive($z, [ $oldmasters ], [ $masters ], 1);
$allow = &bind8::find('allow-update', $z->{'members'});
if ($allow) {
	$oldallow = { %$allow };
	$allow->{'members'} = [ map { { 'name' => $_ } } @mips ];
	&bind8::save_directive($z, [ $oldallow ], [ $allow ], 1);
	}
&flush_file_lines($z->{'file'});
&$virtual_server::second_print($virtual_server::text{'setup_done'});

# Restart BIND
&virtual_server::restart_bind($d);

&ui_print_footer("edit.cgi?dom=$in{'dom'}", $text{'edit_return'});

