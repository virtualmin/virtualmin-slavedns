# Common functions needed for slave DNS management

do '../web-lib.pl';
&init_config();
do '../ui-lib.pl';
&foreign_require('virtual-server', 'virtual-server-lib.pl');

1;

