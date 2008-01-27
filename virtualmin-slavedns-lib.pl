# Common functions needed for slave DNS management

do '../web-lib.pl';
&init_config();
do '../ui-lib.pl';
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

