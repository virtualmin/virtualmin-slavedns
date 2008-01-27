# Defines functions for this feature
# XXX views
# XXX editing master IPs
# XXX backup and restore

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
return $text{'feat_label'};
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
local ($d) = @_;
local $tmpl = &virtual_server::get_template($d->{'template'});
local $mip = $tmpl->{$module_name."master"};
return $mip eq '' || $mip eq 'none' ? $text{'feat_emaster'} : undef;
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
local @mips = split(/\s+/, $tmpl->{$module_name."master"});
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
my $also = { 'name' => 'allow-update',
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

# Add to .conf file
local $pconf;
$dir->{'file'} = &bind8::add_to_file();
$pconf = &bind8::get_config_parent($dir->{'file'});
&bind8::save_directive($pconf, undef, [ $dir ], $indent);
&flush_file_lines($dir->{'file'});
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
	&flush_file_lines($z->{'file'});

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

# feature_backup(&domain, file, &opts, &all-opts)
# Called to backup this feature for the domain to the given file. Must return 1
# on success or 0 on failure
sub feature_backup
{
}

# feature_restore(&domain, file, &opts, &all-opts)
# Called to restore this feature for the domain from the given file. Must
# return 1 on success or 0 on failure
sub feature_restore
{
}

# feature_backup_name()
# Returns a description for what is backed up for this feature
sub feature_backup_name
{
}

# feature_validate(&domain)
# Checks if this feature is properly setup for the virtual server, and returns
# an error message if any problem is found
sub feature_validate
{
}

# template_input(&template)
# Returns HTML for editing per-template options for this plugin
sub template_input
{
local ($tmpl) = @_;
local $v = $tmpl->{$module_name."master"};
$v = "none" if (!defined($v) && $tmpl->{'default'});
return &ui_table_row($text{'tmpl_master'},
	&ui_radio($input_name."_mode",
		$v eq "" ? 0 : $v eq "none" ? 1 : 2,
		[ $tmpl->{'default'} ? ( ) : ( [ 0, $text{'default'} ] ),
		  [ 1, $text{'tmpl_notset'} ],
		  [ 2, $text{'tmpl_ips'} ] ])."\n".
	&ui_textbox($input_name, $v eq "none" ? undef : $v, 30));
}

# template_parse(&template, &in)
# Updates the given template object by parsing the inputs generated by
# template_input. All template fields must start with the module name.
sub template_parse
{
local ($tmpl, $in) = @_;
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
}

1;

