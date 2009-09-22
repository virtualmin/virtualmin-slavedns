# Common functions needed for slave DNS management

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
&init_config();
&foreign_require('virtual-server', 'virtual-server-lib.pl');
%access = &get_module_acl();

sub can_edit_slave
{
local ($dname) = @_;
if ($access{'dom'} eq '*') {
	return 1;
	}
else {
	return &indexof($dname, split(/\s+/, $access{'dom'})) >= 0;
	}
}

1;

