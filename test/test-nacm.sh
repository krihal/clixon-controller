#!/usr/bin/env bash

# Magic line must be first in script (see README.md)
s="$_" ; . ./lib.sh || if [ "$s" = $0 ]; then exit 0; else return 0; fi

# Set if also push, not only change (useful for manually doing push)
: ${push:=true}

: ${check:=false}

# Reset devices with initial config
(. ./reset-devices.sh)

dir=/var/tmp/$0
modules=$dir/modules
fyang=$dir/ssh-users.yang
CFG=$dir/controller.xml
CFD=$dir/conf.d
test -d $dir || mkdir -p $dir
test -d $modules || mkdir -p $modules
test -d $CFD || mkdir -p $CFD
pycode=$modules/ssh-users.py

# Common NACM scripts
. ./nacm.sh

cat <<EOF > $CFG
<clixon-config xmlns="http://clicon.org/config">
  <CLICON_CONFIGFILE>$CFG</CLICON_CONFIGFILE>
  <CLICON_CONFIGDIR>$CFD</CLICON_CONFIGDIR>
  <CLICON_FEATURE>ietf-netconf:startup</CLICON_FEATURE>
  <CLICON_FEATURE>clixon-restconf:allow-auth-none</CLICON_FEATURE>
  <CLICON_CONFIG_EXTEND>clixon-controller-config</CLICON_CONFIG_EXTEND>
  <CLICON_YANG_DIR>${DATADIR}/clixon</CLICON_YANG_DIR>
  <CLICON_YANG_DIR>${DATADIR}/controller/common</CLICON_YANG_DIR>
  <CLICON_YANG_DIR>${DATADIR}/controller/main</CLICON_YANG_DIR>
  <CLICON_YANG_MAIN_DIR>$dir</CLICON_YANG_MAIN_DIR>
  <CLICON_YANG_DOMAIN_DIR>$dir</CLICON_YANG_DOMAIN_DIR>
  <CLICON_CLI_MODE>operation</CLICON_CLI_MODE>
  <CLICON_CLI_DIR>${LIBDIR}/controller/cli</CLICON_CLI_DIR>
  <CLICON_CLISPEC_DIR>${LIBDIR}/controller/clispec</CLICON_CLISPEC_DIR>
  <CLICON_BACKEND_DIR>${LIBDIR}/controller/backend</CLICON_BACKEND_DIR>
  <CLICON_SOCK>${LOCALSTATEDIR}/run/controller.sock</CLICON_SOCK>
  <CLICON_SOCK_GROUP>${CLICON_GROUP}</CLICON_SOCK_GROUP>
  <CLICON_SOCK_PRIO>true</CLICON_SOCK_PRIO>
  <CLICON_BACKEND_PIDFILE>${LOCALSTATEDIR}/run/controller.pid</CLICON_BACKEND_PIDFILE>
  <CLICON_XMLDB_DIR>$dir</CLICON_XMLDB_DIR>
  <CLICON_XMLDB_MULTI>true</CLICON_XMLDB_MULTI>
  <CLICON_STARTUP_MODE>init</CLICON_STARTUP_MODE>
  <CLICON_STREAM_DISCOVERY_RFC5277>true</CLICON_STREAM_DISCOVERY_RFC5277>
  <CLICON_RESTCONF_USER>${CLICON_USER}</CLICON_RESTCONF_USER>
  <CLICON_RESTCONF_PRIVILEGES>drop_perm</CLICON_RESTCONF_PRIVILEGES>
  <CLICON_RESTCONF_INSTALLDIR>${SBINDIR}</CLICON_RESTCONF_INSTALLDIR>
  <CLICON_BACKEND_USER>${CLICON_USER}</CLICON_BACKEND_USER>
  <CLICON_VALIDATE_STATE_XML>true</CLICON_VALIDATE_STATE_XML>
  <CLICON_CLI_HELPSTRING_TRUNCATE>true</CLICON_CLI_HELPSTRING_TRUNCATE>
  <CLICON_CLI_HELPSTRING_LINES>1</CLICON_CLI_HELPSTRING_LINES>
  <CLICON_CLI_OUTPUT_FORMAT>text</CLICON_CLI_OUTPUT_FORMAT>
  <CLICON_YANG_SCHEMA_MOUNT>true</CLICON_YANG_SCHEMA_MOUNT>
  <CLICON_YANG_SCHEMA_MOUNT_SHARE>true</CLICON_YANG_SCHEMA_MOUNT_SHARE>
  <CLICON_YANG_USE_ORIGINAL>true</CLICON_YANG_USE_ORIGINAL>
  <CLICON_NACM_CREDENTIALS>exact</CLICON_NACM_CREDENTIALS>
  <CLICON_NACM_MODE>internal</CLICON_NACM_MODE>
  <CLICON_NACM_CREDENTIALS>none</CLICON_NACM_CREDENTIALS>
  <CLICON_NACM_DISABLED_ON_EMPTY>true</CLICON_NACM_DISABLED_ON_EMPTY>
  <CONTROLLER_ACTION_COMMAND xmlns="http://clicon.org/controller-config">${BINDIR}/clixon_server.py -f $CFG</CONTROLLER_ACTION_COMMAND>
  <CONTROLLER_PYAPI_MODULE_PATH xmlns="http://clicon.org/controller-config">$modules</CONTROLLER_PYAPI_MODULE_PATH>
  <CONTROLLER_PYAPI_MODULE_FILTER xmlns="http://clicon.org/controller-config"></CONTROLLER_PYAPI_MODULE_FILTER>
  <CONTROLLER_PYAPI_PIDFILE xmlns="http://clicon.org/controller-config">/tmp/clixon_pyapi.pid</CONTROLLER_PYAPI_PIDFILE>  <!-- clicon goup cannot write in ${LOCALSTATEDIR} -->
</clixon-config>
EOF

cat <<EOF > $fyang
module ssh-users {
    namespace "http://clicon.org/ssh-users";
    prefix ssh-users;

    import ietf-inet-types { prefix inet; }
    import clixon-controller { prefix ctrl; }
    import clixon-autocli{
        prefix autocli;
    }
    revision 2023-05-22{
        description "Initial prototype";
    }
    augment "/ctrl:services" {
        list ssh-users {
            key service-name;
            leaf service-name {
                type string;
            }
            description "SSH users service";
            list username {
                key name;
                leaf name {
                    type string;
                }
                leaf ssh-key {
                    type string;
                }
                leaf role {
                     type string;
                }
            }
            uses ctrl:created-by-service;
        }
    }
}
EOF

cat <<EOF > $pycode
from clixon.element import Element
from clixon.parser import parse_template

SERVICE = "ssh-users"

USER_XML = """
<user cl:creator="ssh-users[service-name='{{SERVICE_NAME}}']" nc:operation="merge" xmlns:cl="http://clicon.org/lib">
    <username>{{USERNAME}}</username>
    <config>
        <username>{{USERNAME}}</username>
        <ssh-key>{{SSH_KEY}}</ssh-key>
        <role>{{ROLE}}</role>
    </config>
</user>
"""

def setup(root, log, **kwargs):
    try:
        _ = root.services
    except Exception:
        return

    for instance in root.services.ssh_users:
        if instance.service_name != kwargs["instance"]:
            continue
        for user in instance.username:
            service_name = instance.service_name.cdata
            username = user.name.cdata
            ssh_key = user.ssh_key.cdata
            role = user.role.cdata

            new_user = parse_template(USER_XML, SERVICE_NAME=service_name,
                                      USERNAME=username, SSH_KEY=ssh_key, ROLE=role).user

            for device in root.devices.device:
                if device.config.system.get_elements("aaa") == []:
                    device.config.system.create("aaa")
                if device.config.system.aaa.get_elements("authentication") == []:
                    device.config.system.aaa.create("authentication")
                if device.config.system.aaa.authentication.get_elements("users") == []:
                    device.config.system.aaa.authentication.create("users")
                device.config.system.aaa.authentication.users.add(new_user)

if __name__ == "__main__":
    setup()
EOF

# Sleep and verify devices are open
function sleep_open()
{
    for j in $(seq 1 10); do
        new "Verify devices are open"
        ret=$($clixon_cli -1 -f $CFG show connections)
        match1=$(echo "$ret" | grep --null -Eo "openconfig1.*OPEN") || true
        match2=$(echo "$ret" | grep --null -Eo "openconfig2.*OPEN") || true
        if [ -n "$match1" -a -n "$match2" ]; then
            break;
        fi
        echo "retry after sleep"
        sleep 1
    done
    if [ $j -eq 10 ]; then
        err "device openconfig OPEN" "Timeout" 
    fi
}

if $BE; then
    new "Kill old backend"
    stop_backend -f $CFG

    new "Start new backend -s startup -f $CFG"
    start_backend -s startup -f $CFG
fi

SERVICE_DIFF="openconfig1:
  <system>
+     <aaa>
+        <authentication>
+           <users>
+              <user>
+                 <username>test1</username>
+                 <config>
+                    <username>test1</username>
+                    <ssh-key>key1</ssh-key>
+                    <role>admin</role>
+                 </config>
+              </user>
+           </users>
+        </authentication>
+     </aaa>
  </system>
openconfig2:
  <system>
+     <aaa>
+        <authentication>
+           <users>
+              <user>
+                 <username>test1</username>
+                 <config>
+                    <username>test1</username>
+                    <ssh-key>key1</ssh-key>
+                    <role>admin</role>
+                 </config>
+              </user>
+           </users>
+        </authentication>
+     </aaa>
  </system>
OK"

# Get the current user
USERNAME=$(whoami)

new "Wait backend"
wait_backend

# Reset controller 
new "reset controller"
(. ./reset-controller.sh)

new "Close all devices"
expectpart "$($clixon_cli -1 -f $CFG connection close)" 0 ""

new "Connect to devices"
expectpart "$($clixon_cli -1 -f $CFG connection open)" 0 ""

new "Sleep and verify devices are open"
sleep_open

new "Show device diff, should be empty"
expectpart "$($clixon_cli -1 -f $CFG show devices diff)" 0 "^$"

# Verify that service processes are running
new "Verify service processes are running"
expectpart "$($clixon_cli -1 -f $CFG processes service status)" 0 ".*running.*" ""

# NACM tests
new "Create NACM group"
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm groups group test user-name $USERNAME)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test group test)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure commit local)" 0 ""

new "Create default NACM rules"
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm exec-default permit)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm read-default permit)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm write-default permit)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure commit local)" 0 ""


new "Test service, should work"
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1 role admin)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1 ssh-key key1)" 0 ""

# Commit diff
new "Commit diff for user test1"
expectpart "$($clixon_cli -1 -f $CFG -m configure commit diff)" 0 "$SERVICE_DIFF"

Rollback
new "Rollback service configuration"
expectpart "$($clixon_cli -1 -f $CFG -m configure rollback)" 0 ""

new "Create default NACM rules"
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm exec-default deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm read-default deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm write-default deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure commit local)" 0 ""

new "Test service, should work"
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1 role admin)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1 ssh-key key1)" 0 ""

# Commit diff
new "Commit diff for user test1"
expectpart "$($clixon_cli -1 -f $CFG -m configure commit diff)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure rollback)" 0 ""

# Deny change of device address
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name=\"openconfig1\"]/ctrl:addr access-operations \*)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name=\"openconfig1\"]/ctrl:addr action deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name=\"openconfig2\"]/ctrl:addr access-operations \*)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name=\"openconfig2\"]/ctrl:addr action deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure commit local)" 0 ""

# Change device address
new "Change device address"
expectpart "$($clixon_cli -1 -f $CFG -m configure set devices device openconfig1 addr 1.2.3.4)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure commit local)" 0 "" ""

Set NACM for service
new "Set NACM for service, deny all"
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name='openconfig1']/ctrl:config/oc-sys:system access-operations \*)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name='openconfig1']/ctrl:config/oc-sys:system action deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name='openconfig2']/ctrl:config/oc-sys:system access-operations \*)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name='openconfig2']/ctrl:config/oc-sys:system action deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure commit local)" 0 ""

# Configure service again
new "Configure service again"
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1 role admin)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1 ssh-key key1)" 0 ""

# Commit diff, should fail
new "Failing commit diff for user test1"
expectpart "$($clixon_cli -1 -f $CFG -m configure commit diff)" 1 "" ""

# Rollback
new "Rollback service configuration"
expectpart "$($clixon_cli -1 -f $CFG -m configure rollback)" 0 ""

new "Set NACM for service"
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name='openconfig1']/ctrl:config/oc-sys:system access-operations \*)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name='openconfig1']/ctrl:config/oc-sys:system action deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name='openconfig2']/ctrl:config/oc-sys:system access-operations \*)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set nacm rule-list test rule /ctrl:devices/ctrl:device[ctrl:name='openconfig2']/ctrl:config/oc-sys:system action deny)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure commit local)" 0 ""

# Configure service again
new "Configure service again"
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1 role admin)" 0 ""
expectpart "$($clixon_cli -1 -f $CFG -m configure set service ssh-users test1 username test1 ssh-key key1)" 0 ""

# Commit diff, should succeed
new "Failing commit diff for user test1"
expectpart "$($clixon_cli -1 -f $CFG -m configure commit diff)" 0 "" $SERVICE_DIFF


if $BE; then
     new "Kill old backend"
     #stop_backend -f $CFG
fi

endtest
