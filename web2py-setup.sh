# !/bin/bash
function advice(){
	echo "##################################################################"
	echo "############          Installing  Web2py              ############"
	echo "##################################################################"
	echo "This script will:
	1) Install modules needed to run web2py on Fedora and CentOS/RHEL
	2) Install Python 2.6 to /opt and recompile wsgi if not provided
	2) Install web2py in /opt/web-apps/
	3) Configure SELinux and iptables
	5) Create a self signed ssl certificate
	6) Setup web2py with mod_wsgi
	7) Create virtualhost entries so that web2py responds for '/'
	8) Restart Apache.

	You should probably read this script before running it.

	Although SELinux permissions changes have been made,
	further SELinux changes will be required for your personal
	apps. (There may also be additional changes required for the
	bundled apps.)  As a last resort, SELinux can be disabled.

	A simple iptables configuration has been applied.  You may
	want to review it to verify that it meets your needs.

	Finally, if you require a proxy to access the Internet, please
	set up your machine to do so before running this script.

	(author: Charles Law as berubejd
	 updated: Leonardo Cruz Vidal date: 07/27/2013)

	Press ENTER to continue...[ctrl+C to abort]"

	read CONFIRM
}

function update_system(){

	###
	### Updating system
	###

	echo
	echo " - Updating system"
	echo

	# Verify packages are up to date
	yum update -y

}

function move_tmp(){

	###
	###  Copying files to tmp directory
	###
	
	cp ./apache_conf /tmp/
	cp ./rules_iptables /tmp/
	cp ./selinux /tmp/
	
	###
	###  Moving to tmp directory
	###
	
	current_dir=`pwd`

	if [ -d /tmp/setup-web2py/ ]; then
	    mv /tmp/setup-web2py/ /tmp/setup-web2py.old/
	fi

	mkdir -p /tmp/setup-web2py
	cd /tmp/setup-web2py

}

function install_mysql(){

	###
	### Installing mysql
	### 

	echo "Would you like to install mysql-server? y|n"
	read MYSQL
	case $MYSQL in
		y|Y)
			### MySQL install untested!
			# Install mysql packages (optional)
			yum install mysql mysql-server

			# Enable mysql to start at boot (optional)
			chkconfig --levels 235 mysqld on
			service mysqld start

			# Configure mysql security settings (not really optional if mysql installed)
			/usr/bin/mysql_secure_installation
			;;
		*)
			echo 
			echo "No installing mysql-server"
			echo
			;;
	esac
}

function install_python(){

	###
	### Installing python
	###

	# Install required packages
	yum install httpd mod_ssl mod_wsgi wget python

	# Verify we have at least Python 2.5
	typeset -i version_major
	typeset -i version_minor

	version=`rpm --qf %{Version} -q python`
	version_major=`echo ${version} | awk '{split($0, parts, "."); print parts[1]}'`
	version_minor=`echo ${version} | awk '{split($0, parts, "."); print parts[2]}'`

	if [ ! ${version_major} -ge 2 -o ! ${version_minor} -ge 5 ]; then
	    # Setup 2.6 in /opt - based upon
	    # http://markkoberlein.com/getting-python-26-with-django-11-together-on

	    # Check for earlier Python 2.6 install
	    if [ -e /opt/python2.6 ]; then
		# Is Python already installed?
		RETV=`/opt/python2.6/bin/python -V > /dev/null 2>&1; echo $?`
		if [ ${RETV} -eq 0 ]; then
		    python_installed='True'
		else
		    mv /opt/python2.6 /opt/python2.6-old
		fi
	    fi

	    # Install Python 2.6 if it doesn't exist already
	    if [ ! "${python_installed}" == "True" ]; then
		# Install requirements for the Python build
		yum install sqlite-devel zlib-devel

		mkdir -p /opt/python2.6

		# Download and install
		wget http://www.python.org/ftp/python/2.6.4/Python-2.6.4.tgz
		tar -xzf Python-2.6.4.tgz
		cd Python-2.6.4
		./configure --prefix=/opt/python2.6 --with-threads --enable-shared --with-zlib=/usr/include
		make && make install

		cd /tmp/setup-web2py
	    fi

	    # Create links for Python 2.6
	    # even if it was previously installed just to be sure
	    ln -s /opt/python2.6/lib/libpython2.6.so /usr/lib
	    ln -s /opt/python2.6/lib/libpython2.6.so.1.0 /usr/lib
	    ln -s /opt/python2.6/bin/python /usr/local/bin/python
	    ln -s /opt/python2.6/bin/python /usr/bin/python2.6
	    ln -s /opt/python2.6/lib/python2.6.so /opt/python2.6/lib/python2.6/config/

	    # Update linker for new libraries
	    /sbin/ldconfig

	    # Rebuild wsgi to take advantage of Python 2.6
	    yum install httpd-devel

	    cd /tmp/setup-web2py

	    wget http://modwsgi.googlecode.com/files/mod_wsgi-3.3.tar.gz
	    tar -xzf mod_wsgi-3.3.tar.gz
	    cd mod_wsgi-3.3
	    ./configure --with-python=/usr/local/bin/python
	    make &&  make install

	    echo "LoadModule wsgi_module modules/mod_wsgi.so" > /etc/httpd/conf.d/wsgi.conf

	    cd /tmp/setup-web2py
	fi

}

function install_web2py(){

	###
	### Installing web2py
	###

	echo
	echo " - Downloading, installing, and starting web2py"
	echo

	# Create web-apps directory, if required
	if [ ! -d "/opt/web-apps" ]; then
	    mkdir -p /opt/web-apps

	    chmod 755 /opt
	    chmod 755 /opt/web-apps
	fi

	cd /opt/web-apps

	# Download web2py
	if [ -e web2py_src.zip* ]; then
	    rm web2py_src.zip*
	fi

	wget http://web2py.com/examples/static/web2py_src.zip
	unzip web2py_src.zip
	chown -R apache:apache web2py

}

function setup_selinux(){

	###
	### Setup SELinux
	###

	# Set context for Python libraries if Python 2.6 installed
	if [ -d /opt/python2.6 ]; then
	    cd /opt/python2.6
	    chcon -R -t lib_t lib/
	fi

	# Allow http_tmp_exec required for wsgi
	RETV=`setsebool -P httpd_tmp_exec on > /dev/null 2>&1; echo $?`
	if [ ! ${RETV} -eq 0 ]; then
	    # CentOS doesn't support httpd_tmp_exec
	    cd /tmp/setup-web2py

	    # Create the SELinux policy
		. /tmp/selinux
		
	    checkmodule -M -m -o httpd.mod httpd.te
	    semodule_package -o httpd.pp -m httpd.mod
	    semodule -i httpd.pp

	fi

	# Setup the overall web2py SELinux context
	cd /opt
	chcon -R -t httpd_user_content_t web-apps/

	cd /opt/web-apps/web2py/applications

	# Setup the proper context on the writable application directories
	for app in `ls`
	do
	    for dir in databases cache errors sessions private uploads
	    do
		mkdir ${app}/${dir}
		chown apache:apache ${app}/${dir}
		chcon -R -t tmp_t ${app}/${dir}
	    done
	done

}

function conf_iptables(){

	###
	### Configuring iptables
	###

	cd /tmp/setup-web2py

	# Create rules file - based upon
	# http://articles.slicehost.com/assets/2007/9/4/iptables.txt

	. /tmp/rules_iptables

	/sbin/iptables -F
	cat iptables.rules | /sbin/iptables-restore
	/sbin/service iptables save

}

function conf_ssl(){

	###
	### Configuring SSL
	###
	
	echo
	echo " - Creating a self signed certificate"
	echo

	# Verify ssl directory exists
	if [ ! -d "/etc/httpd/ssl" ]; then
	    mkdir -p /etc/httpd/ssl
	fi

	# Generate and protect certificate
	openssl genrsa 1024 > /etc/httpd/ssl/self_signed.key
	openssl req -new -x509 -nodes -sha1 -days 365 -key /etc/httpd/ssl/self_signed.key > /etc/httpd/ssl/self_signed.cert
	openssl x509 -noout -fingerprint -text < /etc/httpd/ssl/self_signed.cert > /etc/httpd/ssl/self_signed.info

	chmod 400 /etc/httpd/ssl/self_signed.*


}

function conf_apache(){

	###
	### Configuring Apache
	###
	
	echo
	echo " - Configure Apache to use mod_wsgi"
	echo

	# Create config
	if [ -e /etc/httpd/conf.d/welcome.conf ]; then
	    mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf.disabled
	fi

	# Configuring apache files
	. /tmp/apache_conf

	# Fix wsgi socket locations
	echo "WSGISocketPrefix run/wsgi" >> /etc/httpd/conf.d/wsgi.conf

	# Restart Apache to pick up changes
	service httpd restart

}

function web2py_admin(){
	
	###
	### Configuring passwords
	###

	echo
	echo " - Setup web2py admin password"
	echo

	cd /opt/web-apps/web2py
	sudo -u apache python -c "from gluon.main import save_password; save_password(raw_input('admin password: '),443)"

}

function service_start(){

	###
	### Services started
	###


	/sbin/chkconfig iptables on
	/sbin/chkconfig httpd on

}

function finished(){
	
	###
	### Finished 
	### 

	# Change back to original directory
	cd ${current_directory}
	
	echo " - Complete!"
	echo
	
	echo 
	echo "You are located in "
	pwd
	echo

}

function install_update(){
	advice			# Credits
	move_tmp		# Don't remove this tag
	update_system	# Updating system (do not remove)
	install_mysql	# Installing mysql (optional)
	install_python	# Installing python2.6
	install_web2py  # Installing web2py	
	setup_selinux	# Setup SELinux
	conf_iptables	# Configuring iptables
	conf_ssl		# Configuring ssl
	conf_apache		# Configuring apache
	web2py_admin	# Configuring passwords
	service_start	# Services started
	finished		# Finished
}

install_update
