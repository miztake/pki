#!/bin/sh
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/rhcs/acceptance/cli-tests/pki-ca-profile-cli
#   Description: PKI CA PROFILE CLI tests
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The following pki key cli commands needs to be tested:
#  pki ca-profile-disable
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Author: Niranjan Mallapadi <mniranja@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2013 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include rhts environment
. /usr/bin/rhts-environment.sh
. /usr/share/beakerlib/beakerlib.sh
. /opt/rhqa_pki/rhcs-shared.sh
. /opt/rhqa_pki/pki-cert-cli-lib.sh
. /opt/rhqa_pki/env.sh

run_pki-ca-profile-disable_tests()
{
        local cs_Type=$1
        local cs_Role=$2

        # Creating Temporary Directory for pki ca-profile-disable
        rlPhaseStartSetup "pki key-show Temporary Directory"
        rlRun "TmpDir=\`mktemp -d\`" 0 "Creating tmp directory"
        rlRun "export PYTHONPATH=$PYTHONPATH:/opt/rhqa_pki/"
        rlRun "pushd $TmpDir"
        rlPhaseEnd

        # Local Variables
        get_topo_stack $cs_Role $TmpDir/topo_file
        local CA_INST=$(cat $TmpDir/topo_file | grep MY_CA | cut -d= -f2)
        local target_unsecure_port=$(eval echo \$${CA_INST}_UNSECURE_PORT)
        local target_secure_port=$(eval echo \$${CA_INST}_SECURE_PORT)
        local tmp_ca_agent=$CA_INST\_agentV
        local tmp_ca_admin=$CA_INST\_adminV
        local tmp_ca_port=$(eval echo \$${CA_INST}_UNSECURE_PORT)
        local tmp_ca_host=$(eval echo \$${cs_Role})
        local valid_agent_cert=$CA_INST\_agentV
        local valid_audit_cert=$CA_INST\_auditV
        local valid_operator_cert=$CA_INST\_operatorV
        local valid_admin_cert=$CA_INST\_adminV
        local revoked_agent_cert=$CA_INST\_agentR
        local revoked_admin_cert=$CA_INST\_adminR
        local expired_admin_cert=$CA_INST\_adminE
        local expired_agent_cert=$CA_INST\_agentE
        local TEMP_NSS_DB="$TmpDir/nssdb"
        local TEMP_NSS_DB_PWD="redhat"
        local cert_info="$TmpDir/cert_info"
        local ca_profile_out="$TmpDir/ca-profile-out"
        local rand=$RANDOM
        local tmp_junk_data=$(openssl rand -base64 50 |  perl -p -e 's/\n//')

        rlPhaseStartTest "pki_ca-profile-disable-config_test: pki ca-profile-disable --help configuration test"
        rlRun "pki ca-profile-disable --help > $ca_profile_out" 0 "pki ca-profile-disable --help"
        rlAssertGrep "usage: ca-profile-disable <Profile ID> \[OPTIONS...\]" "$ca_profile_out"
        rlAssertGrep "    --help   Show help options" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-001: Disabling an existing enabled profile using pki ca-profile-disable should pass"
        local profile="caUserCert"
        rlLog "Disable $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-disable $profile > $ca_profile_out" 
        rlAssertGrep "Disabled profile \"$profile\"" "$ca_profile_out"
        rlLog "Re-Enable profile $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port  \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-enable $profile > $ca_profile_out"
        rlAssertGrep "Enabled profile \"$profile\"" "$ca_profile_out"        
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-002: Create a new profile and verify Disabling the profile succeeds"
        rlLog "Executing pki ca-profile-enable as $valid_admin_cert"
        local profile="caUserTestProfile$RANDOM"
        rlRun "python -m PkiLib.pkiprofilecli --new user --profileId $profile --output $TmpDir/$profile\.xml"
        rlLog "Add $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_admin_cert \
                ca-profile-add $TmpDir/$profile\.xml > $ca_profile_out"
        rlAssertGrep "Added profile $profile" "$ca_profile_out"
        rlLog "Enable profile $caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-enable $profile > $ca_profile_out"
        rlAssertGrep "Enabled profile \"$profile\"" "$ca_profile_out"
        rlLog "Disable profile $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port  \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-disable $profile > $ca_profile_out"
        rlAssertGrep "Disabled profile \"$profile\"" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-003: Executing ca-profile-disable as anonymous user should fail"
        local profile="caUserCert"
        rlLog "Disabling profile $profile as anonymous user"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255 "Execute pki ca-profile-disable $profile as anonymous user"
        rlAssertGrep "ForbiddenException: Anonymous access not allowed" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-004: Verify Disabling a non-existent profile fails"
        local profile="NonExistentProfile"
        rlLog "Enable profile $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" 255 "Disable profile $profile"
        rlAssertGrep "ProfileNotFoundException: Profile ID $profile not found" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-005: Disabling an already Disabled profile should fail"
        rlLog "Executing pki ca-profile-enable as $valid_admin_cert"
        local profile="caUserTestProfile$RANDOM"
        rlRun "python -m PkiLib.pkiprofilecli --new user --profileId $profile --output $TmpDir/$profile\.xml"
        rlLog "Add $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_admin_cert \
                ca-profile-add $TmpDir/$profile\.xml > $ca_profile_out"
        rlAssertGrep "Added profile $profile" "$ca_profile_out"
        rlLog "Enable profile $caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-enable $profile > $ca_profile_out"
        rlAssertGrep "Enabled profile \"$profile\"" "$ca_profile_out"
        rlLog "Disable profile $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port  \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-disable $profile > $ca_profile_out"
        rlAssertGrep "Disabled profile \"$profile\"" "$ca_profile_out"        
        rlLog "Disable profile $profile again"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port  \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Disable already disabled profile $profile"
        rlAssertGrep "BadRequestException: Profile already disabled" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-006: Executing pki ca-profile-disable using valid admin cert should fail"
        rlLog "Executing pki ca-profile-disable as $valid_admin_cert"
        local profile="caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_admin_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Execute ca-profile-disable on $profile"
        rlAssertGrep "ForbiddenException: Authorization Error" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-007: Executing pki ca-profile-disable using valid agent cert should pass"
        rlLog "Executing pki ca-profile-disable as $valid_agent_cert"
        local profile="caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-disable $profile > $ca_profile_out" 0 "Execute ca-profile-disable on $profile"
        rlAssertGrep "Disabled profile \"$profile\"" "$ca_profile_out"
        rlLog "Re-Enable the profile $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port  \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-enable $profile > $ca_profile_out"
        rlAssertGrep "Enabled profile \"$profile\"" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-008: Executing pki ca-profile-disable using revoked admin cert should fail"
        rlLog "Executing pki ca-profile-disable as $revoked_admin_cert"
        local profile="caUserCert" 
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $revoked_admin_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Execute ca-profile-disable on $profile"
        rlAssertGrep "PKIException: Unauthorized" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-009: Executing pki ca-profile-disable using revoked agent cert should fail"
        rlLog "Executing pki ca-profile-disable as $revoked_agent_cert"
        local profile="caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $revoked_agent_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Execute ca-profile-disable on $profile"
        rlAssertGrep "PKIException: Unauthorized" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile-disable-0010: Executing pki ca-profile-disable using expired admin cert should fail"
        rlLog "Executing pki ca-profile-disable as $expired_admin_cert"
        local cur_date=$(date -u)
        local end_date=$(certutil -L -d $CERTDB_DIR -n $expired_admin_cert | grep "Not After" | awk -F ": " '{print $2}')
        rlLog "Current Date/Time: $(date)"
        rlLog "Current Date/Time: before modifying using chrony $(date)"
        rlRun "chronyc -a 'manual on' 1> $TmpDir/chrony.out" 0 "Set chrony to manual mode"
        rlAssertGrep "200 OK" "$TmpDir/chrony.out"
        rlLog "Move system to $end_date + 1 day ahead"
        rlRun "chronyc -a -m 'offline' 'settime $end_date + 1 day' 'makestep' 'manual reset' 1> $TmpDir/chrony.out"
        rlAssertGrep "200 OK" "$TmpDir/chrony.out"
        rlLog "Date after modifying using chrony: $(date)"
        rlLog "Executing pki ca-profile-disable as $expired_admin_cert"
        local profile="caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $expired_admin_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Execute ca-profile-disable on $profile"
        rlAssertGrep "ProcessingException: Unable to invoke request" "$ca_profile_out"        
        rlLog "Set the date back to its original date & time"
        rlRun "chronyc -a -m 'settime $cur_date + 10 seconds' 'makestep' 'manual reset' 'online' 1> $TmpDir/chrony.out"
        rlAssertGrep "200 OK" "$TmpDir/chrony.out"
        rlLog "Current Date/Time after setting system date back using chrony $(date)"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile-disable-0011: Executing pki ca-profile-disable using expired agent cert should fail"
        rlLog "Executing pki ca-profile-disable as $expired_agent_cert"
        local cur_date=$(date -u)
        local end_date=$(certutil -L -d $CERTDB_DIR -n $expired_agent_cert | grep "Not After" | awk -F ": " '{print $2}')
        rlLog "Current Date/Time: $(date)"
        rlLog "Current Date/Time: before modifying using chrony $(date)"
        rlRun "chronyc -a 'manual on' 1> $TmpDir/chrony.out" 0 "Set chrony to manual mode"
        rlAssertGrep "200 OK" "$TmpDir/chrony.out"
        rlLog "Move system to $end_date + 1 day ahead"
        rlRun "chronyc -a -m 'offline' 'settime $end_date + 1 day' 'makestep' 'manual reset' 1> $TmpDir/chrony.out"
        rlAssertGrep "200 OK" "$TmpDir/chrony.out"
        rlLog "Date after modifying using chrony: $(date)"
        local profile="caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $expired_agent_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Execute ca-profile-disable on $profile"
        rlAssertGrep "ProcessingException: Unable to invoke request" "$ca_profile_out"
        rlLog "Set the date back to its original date & time"
        rlRun "chronyc -a -m 'settime $cur_date + 10 seconds' 'makestep' 'manual reset' 'online' 1> $TmpDir/chrony.out"
        rlAssertGrep "200 OK" "$TmpDir/chrony.out"
        rlLog "Current Date/Time after setting system date back using chrony $(date)"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-0012: Executing pki ca-profile-disable using audit cert should fail"
        rlLog "Executing pki ca-profile-disable as $valid_audit_cert"
        local profile="caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_audit_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Execute ca-profile-disable on $profile"
        rlAssertGrep "ForbiddenException: Authorization Error" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-0013: Executing pki ca-profile-disable using operator cert should fail"
        rlLog "Executing pki ca-profile-disable as $valid_operator_cert"
        local profile="caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_operator_cert \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Execute ca-profile-disable on $profile"
        rlAssertGrep "ForbiddenException: Authorization Error" "$ca_profile_out"
        rlPhaseEnd        

        rlPhaseStartSetup "Create a Normal User with No Privileges and add cert"
        local rand=$RANDOM
        local pki_user="idm1_user_$rand"
        local pki_user_fullName="Idm1 User $rand"
        local pki_pwd="Secret123"
        local profile="caUserCert"
        rlLog "Create user $pki_user"
        rlRun "pki -d $CERTDB_DIR \
                -h $tmp_ca_host \
                -p $tmp_ca_port \
                -n $valid_admin_cert \
                -c $CERTDB_DIR_PASSWORD \
                ca-user-add $pki_user \
                --fullName \"$pki_user_fullName\" \
                --password $pki_pwd" 0 "Create $pki_user User"
        rlLog "Generate cert for user $pki_user"
        rlRun "generate_new_cert tmp_nss_db:$TEMP_NSS_DB \
                tmp_nss_db_pwd:$TEMP_NSS_DB_PWD \
                myreq_type:pkcs10 \
                algo:rsa \
                key_size:2048 \
                subject_cn:\"$pki_user_fullName\" \
                subject_uid:$pki_user \
                subject_email:$pki_user@example.org \
                subject_ou: \
                subject_o: \
                subject_c: \
                archive:false \
                req_profile:$profile \
                target_host:$tmp_ca_host \
                protocol: \
                port:$tmp_ca_port \
                cert_db_dir:$CERTDB_DIR \
                cert_db_pwd:$CERTDB_DIR_PASSWORD \
                certdb_nick:$valid_agent_cert \
                cert_info:$cert_info"
        local cert_serialNumber=$(cat $cert_info| grep cert_serialNumber | cut -d- -f2)
        rlLog "Get the $pki_user cert in a output file"
        rlRun "pki -h $tmp_ca_host -p $tmp_ca_port cert-show $cert_serialNumber --encoded --output $TEMP_NSS_DB/$pki_user-out.pem 1> $TEMP_NSS_DB/pki-cert-show.out"
        rlAssertGrep "Certificate \"$cert_serialNumber\"" "$TEMP_NSS_DB/pki-cert-show.out"
        rlRun "pki -h $tmp_ca_host -p $tmp_ca_port cert-show 0x1 --encoded --output  $TEMP_NSS_DB/ca_cert.pem 1> $TEMP_NSS_DB/ca-cert-show.out"
        rlAssertGrep "Certificate \"0x1\"" "$TEMP_NSS_DB/ca-cert-show.out"
        rlLog "Add the $pki_user cert to $TEMP_NSS_DB NSS DB"
        rlRun "pki -d $TEMP_NSS_DB \
                -h $tmp_ca_host \
                -p $tmp_ca_port \
                -c $TEMP_NSS_DB_PWD \
                -n "$pki_user" client-cert-import \
                --cert $TEMP_NSS_DB/$pki_user-out.pem 1> $TEMP_NSS_DB/pki-client-cert.out"
        rlAssertGrep "Imported certificate \"$pki_user\"" "$TEMP_NSS_DB/pki-client-cert.out"
        rlLog "Get CA cert imported to $TEMP_NSS_DB NSS DB"
        rlRun "pki -d $TEMP_NSS_DB \
                -h $tmp_ca_host \
                -p $tmp_ca_port \
                -c $TEMP_NSS_DB_PWD \
                -n \"casigningcert\" client-cert-import \
                --ca-cert $TEMP_NSS_DB/ca_cert.pem 1> $TEMP_NSS_DB/pki-ca-cert.out"
        rlAssertGrep "Imported certificate \"casigningcert\"" "$TEMP_NSS_DB/pki-ca-cert.out"
        rlRun "pki -d $CERTDB_DIR \
                -h $tmp_ca_host \
                -p $tmp_ca_port \
                -n $valid_admin_cert \
                -c $CERTDB_DIR_PASSWORD \
                -t ca user-cert-add $pki_user \
                --input $TEMP_NSS_DB/$pki_user-out.pem 1> $TEMP_NSS_DB/pki_user_cert_add.out" 0 "Cert is added to the user $pki_user"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-0014: Executing pki ca-profile-disable using Normal cert should fail"
        rlLog "Executing pki ca-profile-disable as $pki_user"
        local profile="caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $TEMP_NSS_DB \
                -c $TEMP_NSS_DB_PWD \
                -n $pki_user \
                ca-profile-disable $profile > $ca_profile_out 2>&1" \
                255,1 "Execute ca-profile-disable on $profile"
        rlAssertGrep "ForbiddenException: Authorization Error" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-0015: Executing pki ca-profile-disable using https URI using Agent Cert"
        rlLog "Executing pki ca-profile-disable as $valid_agent_cert"
        rlRun "pki -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -U https://$tmp_ca_host:$target_secure_port \
                -n \"$valid_agent_cert\" \
                ca-profile-disable $profile > $ca_profile_out" 0 "Execute ca-profile-disable on $profile"
        rlssertGrep "Disabled profile \"$profile\"" "$ca_profile_out"
        rlLog "Re-Enable the profile $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port  \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-enable $profile > $ca_profile_out" 0 "Enable $profile"
        rlAssertGrep "Enabled profile \"$profile\"" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-0016: Executing pki ca-profile-disable using Normal user (Not a member of any group) should fail"
        rlLog "Executing pki ca-profile-disable as $pki_user user"
        local profile="caUserCert"
        rlRun "pki -d $CERTDB_DIR \
                 -c $CERTDB_DIR_PASSWORD\
                 -h $tmp_ca_host \
                 -p $tmp_ca_port \
                 -u $pki_user \
                 -w $pki_pwd \
                 ca-profile-disable $profile > $ca_profile_out 2>&1" 255,1 "Execute ca-profile-disable on $profile as $pki_user"
        rlAssertGrep "ForbiddenException: Authentication method not allowed" "$ca_profile_out"
        rlPhaseEnd

        rlPhaseStartTest "pki_ca_profile_disable-0017: Executing pki ca-profile-disable using using invalid user should fail"
        local invalid_pki_user=test1
        local invalid_pki_user_pwd=Secret123
        rlRun "pki -d $CERTDB_DIR \
            -c $CERTDB_DIR_PASSWORD\
            -h $tmp_ca_host \
            -p $tmp_ca_port \
            -u $invalid_pki_user \
            -w $invalid_pki_user_pwd \
            ca-profile-disable $profile > $ca_profile_out 2>&1" 255,1 "Executing ca-profile-disable as $invalid_pki_user"
        rlAssertGrep "PKIException: Unauthorized" "$ca_profile_out"
        rlPhaseEnd

	rlPhaseStartTest "pki_ca_profile_disable-0018: Verify editing of profile succeeds in disabled state"
        local profile="caUserCert$RANDOM"
        local profilename="$profile Enrollment Profile"
        rlLog "Create a new user profile for modification"
        rlRun "python -m PkiLib.pkiprofilecli --new user --profileId $profile --profilename \"$profilename\" --outputfile $TmpDir/$profile-test.xml"
        rlRun "pki -h $tmp_ca_host -p $tmp_ca_port -d $CERTDB_DIR -c $CERTDB_DIR_PASSWORD -n $valid_admin_cert ca-profile-add $TmpDir/$profile-test.xml > $ca_profile_out"
        rlAssertGrep "Added profile $profile" "$ca_profile_out"
        rlLog "Enable profile $caUserCert"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-enable $profile > $ca_profile_out"	
	rlAssertGrep "Enabled profile \"$profile\"" "$ca_profile_out"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port  \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-disable $profile > $ca_profile_out"
        rlAssertGrep "Disabled profile \"$profile\"" "$ca_profile_out"
	rlLog "Modify Profile $profile"
        rlRun "python -m PkiLib.pkiprofilecli \
            --editprofile $TmpDir/$profile-test.xml \
            --notBefore 5 \
            --notAfter 5 \
            --validfor 15 \
            --maxvalidity 30  \
            --outputfile $TmpDir/$profile-mod.xml" 0 "Modify Profile xml"
        rlLog "Add $profile"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_admin_cert \
                ca-profile-mod $TmpDir/$profile-mod.xml > $ca_profile_out" 0 "Update $profile with profile changes"
	rlAssertGrep "Modified profile $profile" "$ca_profile_out"
        rlRun "pki -h $tmp_ca_host \
                -p $tmp_ca_port \
                -d $CERTDB_DIR \
                -c $CERTDB_DIR_PASSWORD \
                -n $valid_agent_cert \
                ca-profile-enable $profile > $ca_profile_out"
	rlAssertGrep "Enabled profile \"$profile\"" "$ca_profile_out"
	rlPhaseEnd

        rlPhaseStartCleanup "pki ca-profile-disable cleanup: Delete temp dir"
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
        rlPhaseEnd    
}
