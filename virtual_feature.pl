# Defines functions for this feature

require 'virtualmin-slavedns-lib.pl';
$input_name = $module_name;
$input_name =~ s/[^A-Za-z0-9]/_/g;

# feature_name()
# Returns a short name for this feature
sub feature_name
{
return $text{'feat_name'};
}

# feature_losing(&domain)
# Returns a description of what will be deleted when this feature is removed
sub feature_losing
{
return $text{'feat_losing'};
}

# feature_label(in-edit-form)
# Returns the name of this feature, as displayed on the domain creation and
# editing form
sub feature_label
{
local ($edit) = @_;
return $edit ? $text{'feat_label2'} : $text{'feat_label'};
}

# feature_hlink(in-edit-form)
# Returns a help page linked to by the label returned by feature_label
sub feature_hlink
{
return 'feat';
}

# feature_check()
# Returns undef if all the needed programs for this feature are installed,
# or an error message if not
sub feature_check
{
return &foreign_installed("bind8", 1) == 2 ? undef :
	&text('feat_echeck', '../bind8/');
}

# feature_depends(&domain)
# Returns undef if all pre-requisite features for this domain are enabled,
# or an error message if not.
# Checks for a default master IP address in template.
sub feature_depends
{
local ($d, $oldd) = @_;
if (!$oldd || !$oldd->{$module_name}) {
	local $tmpl = &virtual_server::get_template($d->{'template'});
	local $mip = $d->{$module_name."master"} ||
		     $tmpl->{$module_name."master"};
	return $text{'feat_emaster'} if ($mip eq '' || $mip eq 'none');
	}
return undef;
}

# feature_clash(&domain)
# Returns undef if there is no clash for this domain for this feature, or
# an error message if so.
# Checks for a DNS zone with the same name.
sub feature_clash
{
local ($d) = @_;
local $z = &virtual_server::get_bind_zone($d->{'dom'});
return $z ? $text{'feat_clash'} :
       $d->{'dns'} ? $text{'feat_clash2'} : undef;
}

# feature_suitable([&parentdom], [&aliasdom], [&subdom])
# Returns 1 if some feature can be used with the specified alias,
# parent and sub domains.
# Doesn't make sense for alias domains.
sub feature_suitable
{
local ($parentdom, $aliasdom, $subdom) = @_;
return !$aliasdom;
}

# feature_setup(&domain)
# Called when this feature is added, with the domain object as a parameter
sub feature_setup
{
local ($d) = @_;
local $tmpl = &virtual_server::get_template($d->{'template'});
local @mips = split(/\s+/, $d->{$module_name."master"} ||
			   $tmpl->{$module_name."master"});
&$virtual_server::first_print($text{'setup_bind'});
if (!@mips) {
	&$virtual_server::second_print($text{'setup_emaster'});
	return 0;
	}
if (defined(&virtual_server::obtain_lock_dns)) {
	&virtual_server::obtain_lock_dns($d, 1);
	}

# Create the slave zone directive
&virtual_server::require_bind();
local $conf = &bind8::get_config();
local $dir = {
	 'name' => 'zone',
	 'values' => [ $d->{'dom'} ],
	 'type' => 1,
	 'members' => [ { 'name' => 'type',
			  'values' => [ 'slave' ] },
			{ 'name' => 'masters',
			  'type' => 1,
			  'members' => [ map { { 'name' => $_ } } @mips ] } ],
	};

# Allow masters to update
my $also = { 'name' => 'allow-notify',
	     'type' => 1,
	     'members' => [ ] };
foreach my $ip (@mips) {
	push(@{$also->{'members'}}, { 'name' => $ip });
	}
push(@{$dir->{'members'}}, $also);

# Create and add slave file
local $base = $bind8::config{'slave_dir'} || &bind8::base_directory();
local $file = &bind8::automatic_filename($d->{'dom'}, 0, $base);
push(@{$dir->{'members'}}, { 'name' => 'file',
			     'values' => [ $file ] } );
&open_tempfile(ZONE, ">".&bind8::make_chroot($file), 0, 1);
&close_tempfile(ZONE);
&bind8::set_ownership(&bind8::make_chroot($file));

# Work out where to add
local $pconf;
local $indent = 0;
if ($tmpl->{$module_name.'view'}) {
	# Adding inside a view. This may use named.conf, or an include
	# file references inside the view, if any
	$pconf = &bind8::get_config_parent();
	local $view = &virtual_server::get_bind_view($conf,
			$tmpl->{$module_name.'view'});
	if ($view) {
		local $addfile = &bind8::add_to_file();
		local $addfileok;
		if ($bind8::config{'zones_file'} &&
		    $view->{'file'} ne $bind8::config{'zones_file'}) {
			# BIND module config asks for a file .. make
			# sure it is included in the view
			foreach my $vm (@{$view->{'members'}}) {
				if ($vm->{'file'} eq $addfile) {
					# Add file is OK
					$addfileok = 1;
					}
				}
			}

		if (!$addfileok) {
			# Add to named.conf
			$pconf = $view;
			$indent = 1;
			$dir->{'file'} = $view->{'file'};
			}
		else {
			# Add to the file
			$dir->{'file'} = $addfile;
			$pconf = &bind8::get_config_parent($addfile);
			}
		}
	else {
		&error(&virtual_server::text('setup_ednsview',
			     $tmpl->{$module_name.'view'}));
		}
	}
else {
	# Adding at top level .. but perhaps in a different file
	$dir->{'file'} = &bind8::add_to_file();
	$pconf = &bind8::get_config_parent($dir->{'file'});
	}

# Add to .conf file
&bind8::save_directive($pconf, undef, [ $dir ], $indent);
&flush_file_lines(&bind8::make_chroot($dir->{'file'}));
unlink($bind8::zone_names_cache);
undef(@bind8::list_zone_names_cache);

if (defined(&virtual_server::release_lock_dns)) {
	&virtual_server::release_lock_dns($d, 1);
	}

# All done
&virtual_server::register_post_action(\&virtual_server::restart_bind);
&$virtual_server::second_print(&text('setup_done', join(' ', @mips)));
return 1;
}

# feature_modify(&domain, &olddomain)
# Called when a domain with this feature is modified.
# Renames the zone and file if the domain name is changed.
sub feature_modify
{
local ($d, $oldd) = @_;
if ($d->{'dom'} ne $oldd->{'dom'}) {
	&$virtual_server::first_print($text{'modify_bind'});

	if (defined(&virtual_server::obtain_lock_dns)) {
		&virtual_server::obtain_lock_dns($d, 1);
		}

	# Get the zone object
	local $z = &virtual_server::get_bind_zone($oldd->{'dom'});
	if ($z) {
		# Rename records file, for real and in .conf
		local $file = &bind8::find("file", $z->{'members'});
		local $fn = $file->{'values'}->[0];
		$nfn = $fn;
                $nfn =~ s/$oldd->{'dom'}/$d->{'dom'}/;
                if ($fn ne $nfn) {
                        &rename_logged(&bind8::make_chroot($fn),
                                       &bind8::make_chroot($nfn))
                        }
                $file->{'values'}->[0] = $nfn;
                $file->{'value'} = $nfn;

                # Change zone in .conf file
                $z->{'values'}->[0] = $d->{'dom'};
                $z->{'value'} = $d->{'dom'};
                &bind8::save_directive(&bind8::get_config_parent(),
                                       [ $z ], [ $z ], 0);
                &flush_file_lines();

		# Clear zone names caches
		unlink($bind8::zone_names_cache);
		undef(@bind8::list_zone_names_cache);
		}
	else {
		&$virtual_server::second_print(
			$virtual_server::text{'save_nobind'});
		}

	if (defined(&virtual_server::release_lock_dns)) {
		&virtual_server::release_lock_dns($d, 1);
		}

	# All done
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	return 1;
	}
return 1;
}

# feature_delete(&domain)
# Called when this feature is disabled, or when the domain is being deleted
sub feature_delete
{
local ($d) = @_;
&$virtual_server::first_print($text{'delete_bind'});

if (defined(&virtual_server::obtain_lock_dns)) {
	&virtual_server::obtain_lock_dns($d, 1);
	}

# Get the zone object
local $z = &virtual_server::get_bind_zone($d->{'dom'});
if ($z) {
	# Delete records file
	local $file = &bind8::find("file", $z->{'members'});
	if ($file) {
		local $zonefile =
		    &bind8::make_chroot($file->{'values'}->[0]);
		&unlink_file($zonefile);
		}

	# Delete from .conf file
	local $rootfile = &bind8::make_chroot($z->{'file'});
	local $lref = &read_file_lines($rootfile);
	splice(@$lref, $z->{'line'}, $z->{'eline'} - $z->{'line'} + 1);
	&flush_file_lines($rootfile);

	# Clear zone names caches
	unlink($bind8::zone_names_cache);
	undef(@bind8::list_zone_names_cache);

	&virtual_server::register_post_action(\&virtual_server::restart_bind);
	}
else {
	&$virtual_server::second_print($virtual_server::text{'save_nobind'});
	}

if (defined(&virtual_server::release_lock_dns)) {
	&virtual_server::release_lock_dns($d, 1);
	}

# All done
&$virtual_server::second_print($virtual_server::text{'setup_done'});
return 1;
}

# feature_import(domain-name, user-name, db-name)
# Returns 1 if this feature is already enabled for some domain being imported,
# or 0 if not
sub feature_import
{
local ($dname, $user, $db) = @_;
local $z = &virtual_server::get_bind_zone($d->{'dom'});
if ($z) {
	local $type = &bind8::find("type", $z->{'members'});
	if ($type && ($type->{'values'}->[0] eq 'slave' ||
		      $type->{'values'}->[0] eq 'stub')) {
		return 1;
		}
	}
return 0;
}

# feature_links(&domain)
# Returns an array of link objects for webmin modules for this feature
sub feature_links
{
local ($d) = @_;
return ( { 'mod' => $module_name,
           'desc' => $text{'links_link'},
           'page' => 'edit.cgi?dom='.$d->{'dom'},
           'cat' => 'server',
         } );
}

# feature_webmin(&main-domain, &all-domains)
# Returns a list of webmin module names and ACL hash references to be set for
# the Webmin user when this feature is enabled
sub feature_webmin
{
local @doms = map { $_->{'dom'} } grep { $_->{$module_name} } @{$_[1]};
if (@doms) {
        return ( [ $module_name,
                   { 'dom' => join(" ", @doms),
                     'noconfig' => 1 } ] );
        }
else {
        return ( );
        }
}

sub feature_modules
{
return ( [ $module_name, $text{'feat_module'} ] );
}

# feature_backup(&domain, file, &opts, &all-opts)
# Called to backup this feature for the domain to the given file. Must return 1
# on success or 0 on failure.
# Saves the named.conf block for this domain.
sub feature_backup
{
local ($d, $file) = @_;
&$virtual_server::first_print($text{'backup_conf'});
local $z = &virtual_server::get_bind_zone($d->{'dom'});
if ($z) {
	local $lref = &read_file_lines($z->{'file'}, 1);
	local $dstlref = &read_file_lines($file);
	@$dstlref = @$lref[$z->{'line'} .. $z->{'eline'}];
	&flush_file_lines($file);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	return 1;
	}
else {
	&$virtual_server::second_print($virtual_server::text{'backup_dnsnozone'});
	return 0;
	}
}

# feature_restore(&domain, file, &opts, &all-opts)
# Called to restore this feature for the domain from the given file. Must
# return 1 on success or 0 on failure
sub feature_restore
{
local ($d, $file) = @_;
&$virtual_server::first_print($text{'restore_conf'});

if (defined(&virtual_server::obtain_lock_dns)) {
	&virtual_server::obtain_lock_dns($d, 1);
	}

local $z = &virtual_server::get_bind_zone($d->{'dom'});
local $rv;
if ($z) {
	local $rootfile = &bind8::make_chroot($z->{'file'});
	local $lref = &read_file_lines($rootfile);
	local $srclref = &read_file_lines($file, 1);
	splice(@$lref, $z->{'line'}, $z->{'eline'}-$z->{'line'}+1, @$srclref);
	&flush_file_lines($rootfile);

	&virtual_server::register_post_action(\&virtual_server::restart_bind);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	$rv = 1;
	}
else {
	&$virtual_server::second_print(
		$virtual_server::text{'backup_dnsnozone'});
	$rv = 0;
	}

if (defined(&virtual_server::release_lock_dns)) {
	&virtual_server::release_lock_dns($d, 1);
	}
return $rv;
}

# feature_backup_name()
# Returns a description for what is backed up for this feature
sub feature_backup_name
{
return $text{'backup_name'};
}

# feature_validate(&domain)
# Checks if this feature is properly setup for the virtual server, and returns
# an error message if any problem is found.
# Checks if the zone exists and is a slave.
sub feature_validate
{
local ($d) = @_;
local $z = &virtual_server::get_bind_zone($d->{'dom'});
if ($z) {
	local $type = &bind8::find("type", $z->{'members'});
	if ($type && ($type->{'values'}->[0] eq 'slave' ||
		      $type->{'values'}->[0] eq 'stub')) {
		return undef;
		}
	return $text{'validate_etype'};
	}
return $text{'validate_ezone'};
}

# Always show master DNS server input
sub feature_inputs_show
{
return 1;
}

# feature_inputs([&domain])
# Returns a field for master DNS server(s)
sub feature_inputs
{
local ($d) = @_;
local $tmpl = &virtual_server::get_template($d ? $d->{'template'} : 0);
return &ui_table_row($text{'feat_master'},
	&ui_opt_textbox($input_name."_master",
			$tmpl->{$module_name."master"}, 30,
			$text{'feat_mastertmpl'}));
}

# feature_inputs_parse(&domain, &in)
# Update the domain object with a custom master DNS server
sub feature_inputs_parse
{
local ($d, $in) = @_;
if (defined($in->{$input_name."_master"}) &&
    !$in->{$input_name."_master_def"}) {
	local @ips = split(/\s+/, $in->{$input_name."_master"});
	foreach my $ip (@ips) {
		&check_ipaddress($ip) || return &text('tmpl_eip', $ip);
		}
	@ips || return $text{'tmpl_eips'};
	$d->{$module_name."master"} = $in->{$input_name."_master"};
	}
return undef;
}

# feature_args(&domain)
# Return command-line arguments for domain registration
sub feature_args
{
return ( { 'name' => $module_name."-master",
	   'value' => 'nameservers',
	   'opt' => 1,
	   'desc' => 'Master DNS servers for slave domain' },
       );
}

# feature_args_parse(&domain, &args)
# Parse command-line arguments from feature_args
sub feature_args_parse
{
local ($d, $args) = @_;
if (defined($args->{$module_name."-master"})) {
	local @ips = split(/\s+/, $args->{$module_name."-master"});
	foreach my $ip (@ips) {
		&check_ipaddress($ip) || return "Invalid master DNS server IP address $ip";
		}
	@ips || return "No master DNS server IP addresses given";
	$d->{$module_name."master"} = join(" ", @ips);
	}
return undef;
}

# template_input(&template)
# Returns HTML for editing per-template options for this plugin
sub template_input
{
local ($tmpl) = @_;

# Master IPs input
local $v = $tmpl->{$module_name."master"};
$v = "none" if (!defined($v) && $tmpl->{'default'});
local $rv;
$rv .= &ui_table_row($text{'tmpl_master'},
	&ui_radio($input_name."_mode",
		$v eq "" ? 0 : $v eq "none" ? 1 : 2,
		[ $tmpl->{'default'} ? ( ) : ( [ 0, $text{'default'} ] ),
		  [ 1, $text{'tmpl_notset'} ],
		  [ 2, $text{'tmpl_ips'} ] ])."\n".
	&ui_textbox($input_name, $v eq "none" ? undef : $v, 30));

# Add to view input, if any
&virtual_server::require_bind();
local $conf = &bind8::get_config();
local @views = &bind8::find("view", $conf);
if (@views) {
	$rv .= &ui_table_row($text{'tmpl_view'},
                &ui_select($input_name."_view", $tmpl->{$module_name."view"},
                        [ [ "", $virtual_server::text{'newdns_noview'} ],
                          map { [ $_->{'values'}->[0] ] } @views ]));
	}

return $rv;
}

# template_parse(&template, &in)
# Updates the given template object by parsing the inputs generated by
# template_input. All template fields must start with the module name.
sub template_parse
{
local ($tmpl, $in) = @_;

# Parse master IPs field
if ($in->{$input_name.'_mode'} == 0) {
        $tmpl->{$module_name."master"} = "";
        }
elsif ($in->{$input_name.'_mode'} == 1) {
        $tmpl->{$module_name."master"} = "none";
        }
else {
	local @ips = split(/\s+/, $in->{$input_name});
	foreach my $ip (@ips) {
		&check_ipaddress($ip) || &error(&text('tmpl_eip', $ip));
		}
	@ips || &error($text{'tmpl_eips'});
        $tmpl->{$module_name."master"} = join(" ", @ips);
        }

# Parse view field
if (defined($in->{$input_name.'_view'})) {
	$tmpl->{$module_name."view"} = $in->{$input_name.'_view'};
	}
}

1;

