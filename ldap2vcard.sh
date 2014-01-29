#! /bin/bash

#-------------------------------------#
#            LDAP2vCard               #
#-------------------------------------#
#                                     #
#    Export contact informations      #
#   from LDAP branch to vCard file    #
#                                     #
#             Yvan Godard             #
#        godardyvan@gmail.com         #
#                                     #
# Version α 0.4 -- decemeber, 24 2013 #
#         Tool licenced under         #
#   Creative Commons 4.0 BY NC SA     #
#                                     #
#         http://goo.gl/i3gpVV        #
#                                     #
#-------------------------------------#

# Variables initialisation
VERSION="LDAP2vCard α 0.4 -- 2013 -- http://goo.gl/i3gpVV"
help="no"
SCRIPT_DIR=$(dirname $0)
SCRIPT_NAME=$(basename $0)
EMAIL_REPORT="nomail"
EMAIL_LEVEL=0
LOG="/var/log/ldap2vcard.log"
LOG_ACTIVE=0
LOG_TEMP=$(mktemp /tmp/LDAP2vCard_LOG.XXXXX)
GROUP_LIMIT=0
LIST_GROUPS=$(mktemp /tmp/LDAP2vCard_group_list.XXXXX)
LIST_USERS=$(mktemp /tmp/LDAP2vCard_users_list.XXXXX)
LIST_USERS_CLEAN=$(mktemp /tmp/LDAP2vCard_users_list_clean.XXXXX)
LIST_GROUP_MEMBERS=$(mktemp /tmp/LDAP2vCard_group_members.XXXXX)
DIR_TEMP_USERS=/tmp/LDAP2vCardUsers
LDAP_URL="ldap://127.0.0.1"
LDAP_DN_USER_BRANCH="cn=users"
PATH_EXPORT_VCARD=${SCRIPT_DIR}
DATAFILENAME="LDAP2vCard-$(date +%d.%m.%y-%Hh%M)"

help () {
	echo -e "$VERSION\n"
	echo -e "This tool is designed to export to vCard file informations related to users registered in a (or some) LDAP group."
	echo -e "It works both with LDAP groups defined by objectClass posixGroup or groupOfNames."
	echo -e "This tool is licensed under the Creative Commons 4.0 BY NC SA licence."
	echo -e "\nDisclamer:"
	echo -e "This tool is provide without any support and guarantee."
	echo -e "\nSynopsis:"
	echo -e "./${SCRIPT_NAME} [-h] | -d <base namespace> -a <LDAP admin UID> -p <LDAP admin password>"
	echo -e "                [-s <LDAP server>] [-u <relative DN of user banch>]"
	echo -e "                [-D <main domain for emails>] [-P <Path folder to export>] [-N <Name of export file>]"
	echo -e "                [-G <groups to export> -t <LDAP group objectClass> -g <relative DN of LDAP group base>]"
	echo -e "                [-e <email report option>] [-E <email address>] [-j <log file>]"
	echo -e "\n\t-h:                               prints this help then exit"
	echo -e "\nMandatory options:"
	echo -e "\t-d <base namespace>:              the base DN for each LDAP entry (i.e.: 'dc=server,dc=office,dc=com')"
	echo -e "\t-a <LDAP admin UID>:              UID of the LDAP administrator (i.e.: 'diradmin')"
	echo -e "\t-p <LDAP admin password>:         the password of the LDAP administrator (asked if missing)"
	echo -e "\nOptional options:"
	echo -e "\t-s <LDAP server>:                 the LDAP server URL (default: '$LDAP_URL')"
	echo -e "\t-u <relative DN of user banch>:   the relative DN of the LDAP branch that contains the users (i.e.: 'cn=allusers', default: '$LDAP_DN_USER_BRANCH')"
	echo -e "\t-D <main domain for emails>:      will mark addresses containing this domain as 'TYPE=PREF' in vCard (i.e.: 'mydomain.fr')"
	echo -e "\t-G <groups to export>:            use this option to limit export to on ore some groups, separated by '%' (i.e.: 'workgroup%team2')"
	echo -e "\t                                  or use 'allgroups' for all users registed in one or some groups"
	echo -e "\t-t <LDAP group objectClass>:      the type of groups you want to export, must be 'posixGroup' or 'groupOfNames', must be filled if '-G' is used"	
	echo -e "\t-g <relative DN of LDAP group>:   the relative DN of the LDAP branch that contains groups (i.e.: 'cn=groups' or 'ou=groups'...) - must be filled if '-G' is used"
	echo -e "\t-P <Path folder to export>:       the folder where your want to export your vCard (i.e.: '~/Desktop/' or '/var/vcard/'...), by default ${PATH_EXPORT_VCARD}"
	echo -e "\t-N <Name of export file>:         the name of exported file, without spaces and extension (i.e.: 'myExportvCard'), by default ${DATAFILENAME}"
	echo -e "\t-e <email report option>:         settings for sending a report by email, must be 'onerror', 'forcemail' or 'nomail' (default: '$EMAIL_REPORT')"
	echo -e "\t-E <email address>:               email address to send the report, must be filled if '-e forcemail' or '-e onerror' options is used"
	echo -e "\t-j <log file>:                    enables logging instead of standard output. Specify an argument for the full path to the log file"
	echo -e "\t                                  (i.e.: '$LOG') or use 'default' ($LOG)"
	exit 0
}

error () {
	echo -e "\n*** Error ***"
	echo -e ${1}
	echo -e "\n"${VERSION}
	alldone 1
}

alldone () {
	# Redirect standard outpout
	exec 1>&6 6>&-
	# Logging if needed 
	[ $LOG_ACTIVE -eq 1 ] && cat $LOG_TEMP >> $LOG
	# Print current log to standard outpout
	[ $LOG_ACTIVE -ne 1 ] && cat $LOG_TEMP
	[ $EMAIL_LEVEL -ne 0 ] && [ $1 -ne 0 ] && cat $LOG_TEMP | mail -s "[ERROR] ${SCRIPT_NAME} on ${HOSTNAME}" ${EMAIL_ADDRESS}
	[ $EMAIL_LEVEL -eq 2 ] && [ $1 -eq 0 ] && cat $LOG_TEMP | mail -s "[OK] ${SCRIPT_NAME} on ${HOSTNAME}" ${EMAIL_ADDRESS}
	# Remove temp files/folder
	rm -R /tmp/LDAP2vCard*
	exit ${1}
}

base64decode () {
	echo ${1} | grep :: > /dev/null 2>&1
	if [ $? -eq 0 ] 
		then
		VALUE=$(echo ${1} | grep :: | awk '{print $2}' | openssl enc -base64 -d )
		ATTRIBUTE=$(echo ${1} | grep :: | awk '{print $1}' | awk 'sub( ".$", "" )' )
		echo "${ATTRIBUTE} ${VALUE}"
	else
		echo ${1}
	fi
}

# Remove old temp and create new temp dir
rm -R /tmp/LDAP2vCard*
mkdir -p ${DIR_TEMP_USERS}

optsCount=0
optsCount_limit_groups=0

while getopts "hd:a:p:t:g:s:u:D:G:P:e:E:j:N:" OPTION
do
	case "$OPTION" in
		h)	help="yes"
						;;
		d)	LDAP_DN_BASE=${OPTARG}
			let optsCount=$optsCount+1
						;;
		a)	LDAP_ADMIN_UID=${OPTARG}
			let optsCount=$optsCount+1
						;;
		p)	LDAP_ADMIN_PASS=${OPTARG}
                        ;;
	    s) 	LDAP_URL=${OPTARG}
						;;
		u) 	LDAP_DN_USER_BRANCH=${OPTARG}
						;;
		D)	MAIN_DOMAIN=${OPTARG}
                        ;;
		G)	LDAP_GROUPS=${OPTARG}
			if [[ ${LDAP_GROUPS} != "allgroups" ]] 
				then
				echo ${LDAP_GROUPS} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> $LIST_GROUPS
				GROUP_LIMIT=1
			elif [[ ${LDAP_GROUPS} = "allgroups" ]]
				then
				GROUP_LIMIT=2
			fi
                        ;;
        t)	LDAP_GROUP_OBJECTCLASS=${OPTARG}
			let optsCount_limit_groups=$optsCount_limit_groups+1
                        ;;
		g)	LDAP_GROUP_DN=${OPTARG}
			let optsCount_limit_groups=$optsCount_limit_groups+1
                        ;;
        P)	PATH_EXPORT_VCARD=${OPTARG}
                        ;;
        N)	DATAFILENAME=${OPTARG}
                        ;;
        e)	EMAIL_REPORT=${OPTARG}
                        ;;                             
        E)	EMAIL_ADDRESS=${OPTARG}
                        ;;
        j)	[ $OPTARG != "default" ] && LOG=${OPTARG}
			LOG_ACTIVE=1
                        ;;
	esac
done

if [[ ${optsCount} != "2" ]]
	then
        help
        alldone 1
fi

if [[ ${help} = "yes" ]]
	then
	help
fi

if [[ ${LDAP_ADMIN_PASS} = "" ]]
	then
	echo "Password for uid=$LDAP_ADMIN_UID,$LDAP_DN_USER_BRANCH,$LDAP_DN_BASE?" 
	read -s LDAP_ADMIN_PASS
fi

# Verification of DATANAME
if [[ ${DATAFILENAME} = "" ]]
	then
	DATANAME="LDAP2vCard-$(date +%d.%m.%y-%Hh%M).vcf"
	else
	DATANAME=${DATAFILENAME}.vcf
fi

# Redirect standard outpout to temp file
exec 6>&1
exec >> $LOG_TEMP

# Start temp log file
echo -e "\n****************************** `date` ******************************\n"
echo -e "$0 started with options:"
echo -e "\t-d ${LDAP_DN_BASE} (base namespace)"
echo -e "\t-a ${LDAP_ADMIN_UID} (LDAP admin UID)"
echo -e "\t-s ${LDAP_URL} (LDAP server)"
echo -e "\t-u ${LDAP_DN_USER_BRANCH} (relative DN of user banch)"
[[ ${MAIN_DOMAIN} != "" ]] && echo -e "\t-D ${MAIN_DOMAIN} (main domain for emails)"
if [[ ${GROUP_LIMIT} != "0" ]]
	then
	echo -e "\t-G ${LDAP_GROUPS} (limit export to these groups)"
	echo -e "\t-t ${LDAP_GROUP_OBJECTCLASS} (LDAP group objectClass)"
	echo -e "\t-g ${LDAP_GROUP_DN} (relative DN of LDAP groups base)"
fi
echo -e "\t-e ${EMAIL_REPORT} (email report option)"
if [[ ${EMAIL_REPORT} != "nomail" ]] 
	then
	echo -e "\t-E ${EMAIL_ADDRESS} (email report address)"
fi
if [[ ${LOG_ACTIVE} != "0" ]]
	then
	echo -e "\t-j ${LOG} (log file)"
fi
echo -e "Export to ${PATH_EXPORT_VCARD}/${DATANAME}"

# Need '-t' and '-g' to be filled if '-G' is used
[[ ${GROUP_LIMIT} != "0" ]] && [[ ${optsCount_limit_groups} != "2" ]] && error "Trying to use '-G' option but '-t <LDAP group objectClass>' and '-g <relative DN of LDAP group>' are not filled." 

# Verification of LDAP_GROUP_OBJECTCLASS parameter
[[ ${GROUP_LIMIT} != "0" ]] && [[ ${LDAP_GROUP_OBJECTCLASS} != "posixGroup" ]] && [[ ${LDAP_GROUP_OBJECTCLASS} != "groupOfNames" ]] && error "Parameter '-t ${LDAP_GROUP_OBJECTCLASS}' is not correct.\n-t must be 'posixGroup' or 'groupOfNames'"

# Path to export needs to be a valid folder
if [[ ${PATH_EXPORT_VCARD} != ${SCRIPT_DIR} ]]
	then
	[[ ! -d  ${PATH_EXPORT_VCARD} ]] && echo -e "This export path filled with '-P ${PATH_EXPORT_VCARD}' doesn't exist. Export will be done at ${SCRIPT_DIR}." && PATH_EXPORT_VCARD=${SCRIPT_DIR}
fi

# Test of sending email parameter and check the consistency of the parameter email address
if [[ ${EMAIL_REPORT} = "forcemail" ]]
	then
	EMAIL_LEVEL=2
	if [[ -z ${EMAIL_ADDRESS} ]]
		then
		echo -e "You use option '-e ${EMAIL_REPORT}' but you have not entered any email info.\n\t-> We continue the process without sending email."
		EMAIL_LEVEL=0
	else
		echo "${EMAIL_ADDRESS}" | grep '^[a-zA-Z0-9._-]*@[a-zA-Z0-9._-]*\.[a-zA-Z0-9._-]*$' > /dev/null 2>&1
		if [ $? -ne 0 ]
			then
    		echo -e "This address '${EMAIL_REPORT}' does not seem valid.\n\t-> We continue the process without sending email."
    		EMAIL_LEVEL=0
    	fi
    fi
elif [[ ${EMAIL_REPORT} = "onerror" ]]
	then
	EMAIL_LEVEL=1
	if [[ -z ${EMAIL_ADDRESS} ]]
		then
		echo -e "You use option '-e ${EMAIL_REPORT}' but you have not entered any email info.\n\t-> We continue the process without sending email."
		EMAIL_LEVEL=0
	else
		echo "${EMAIL_ADDRESS}" | grep '^[a-zA-Z0-9._-]*@[a-zA-Z0-9._-]*\.[a-zA-Z0-9._-]*$' > /dev/null 2>&1
		if [ $? -ne 0 ]
			then	
    		echo -e "This address '${EMAIL_REPORT}' does not seem valid.\n\t-> We continue the process without sending email."
    		EMAIL_LEVEL=0
    	fi
    fi
elif [[ ${EMAIL_REPORT} != "nomail" ]]
	then
	echo -e "\nOption '-e ${EMAIL_REPORT}' is not valid (must be: 'onerror', 'forcemail' or 'nomail').\n\t-> We continue the process without sending email."
	EMAIL_LEVEL=0
elif [[ ${EMAIL_REPORT} = "nomail" ]]
	then
	EMAIL_LEVEL=0
fi

# LDAP connection test
echo -e "\nConnecting LDAP at $LDAP_URL ..."

LDAP_COMMAND_BEGIN="ldapsearch -LLL -H ${LDAP_URL} -D uid=${LDAP_ADMIN_UID},${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} -w ${LDAP_ADMIN_PASS}"
${LDAP_COMMAND_BEGIN} -b ${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} > /dev/null 2>&1
if [ $? -ne 0 ]
	then 
	error "Error connecting to LDAP server.\nPlease verify your URL and user/pass."
fi

# Export user list : all users registered in LDAP
if [[ ${GROUP_LIMIT} = "0" ]]
	then
	echo -e "\nExporting all users..."
	${LDAP_COMMAND_BEGIN} -b ${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} uid | grep uid: | awk '{print $2}' >> ${LIST_USERS}
fi

# Test bind to ${LDAP_GROUP_DN},${LDAP_DN_BASE}
if [[ ${GROUP_LIMIT} != "0" ]]
	then
	${LDAP_COMMAND_BEGIN} -b ${LDAP_GROUP_DN},${LDAP_DN_BASE} > /dev/null 2>&1
	[ $? -ne 0 ] && error "Error binding to LDAP server at ${LDAP_GROUP_DN},${LDAP_DN_BASE}.\nPlease verify your URL and user/pass."
fi

# Export user list : all users registered in some groups
if [[ ${GROUP_LIMIT} = "2" ]]
	then
	echo -e "\nExporting users registered in one or some groups in ${LDAP_GROUP_DN},${LDAP_DN_BASE}:"
	if [[ -z $(${LDAP_COMMAND_BEGIN} -b ${LDAP_GROUP_DN},${LDAP_DN_BASE} cn | grep cn: | awk '{print $2}') ]] 
		then 
		error "No group found in ${LDAP_GROUP_DN},${LDAP_DN_BASE}"
	else
		${LDAP_COMMAND_BEGIN} -b ${LDAP_GROUP_DN},${LDAP_DN_BASE} cn | grep cn: | awk '{print $2}' | grep -v $(echo ${LDAP_GROUP_DN} | awk -F'=' '{print $2}')  >> ${LIST_GROUPS}
	fi
fi

# Test group parameters if -G used
[[ ${GROUP_LIMIT} = "1" ]] && [[ -z $(cat ${LIST_GROUPS}) ]] && error "Trying to use '-G' with any group name or parameter 'allgroups'. Please re-try with minimum a group name"

# Export users : all users registered in groups selected
if [[ ${GROUP_LIMIT} != "0" ]]
	then
	echo -e "\nExporting users in groups below, objectClass ${LDAP_GROUP_OBJECTCLASS}:"
	echo -e "$(cat ${LIST_GROUPS} | perl -p -e 's/\n/ - /g' | awk 'sub( "...$", "" )')\n"
	for GROUP in $(cat ${LIST_GROUPS})
	do
	CONTENT_GROUP=$(mktemp /tmp/LDAP2vCard_group_content.XXXXX)
	${LDAP_COMMAND_BEGIN} -b cn=${GROUP},${LDAP_GROUP_DN},${LDAP_DN_BASE} > /dev/null 2>&1
	if [ $? -ne 0 ]
		then 
		echo -e "-> Error binding wth group '${GROUP}' (cn=${GROUP},${LDAP_GROUP_DN},${LDAP_DN_BASE}).\n\tPlease verify this group exists on LDAP."
	elif [[ ${LDAP_GROUP_OBJECTCLASS} = "groupOfNames" ]] 
		then
		echo -e "-> Processing group '${GROUP}'"
		if [[ -z $(${LDAP_COMMAND_BEGIN} -b cn=${GROUP},${LDAP_GROUP_DN},${LDAP_DN_BASE} member | grep member: | awk '{print $2}' | awk -F',' '{print $1}' | awk -F'=' '{print $2}') ]] 
			then 
			echo -e "\tUser list on LDAP group is empty"
		else
			${LDAP_COMMAND_BEGIN} -b cn=${GROUP},${LDAP_GROUP_DN},${LDAP_DN_BASE} member | grep member: | awk '{print $2}' | awk -F',' '{print $1}' | awk -F'=' '{print $2}' >> ${CONTENT_GROUP}
		fi
	elif [[ ${LDAP_GROUP_OBJECTCLASS} = "posixGroup" ]]
		then
		echo -e "-> Processing group '${GROUP}'"
		if [[ -z $(${LDAP_COMMAND_BEGIN} -b cn=${GROUP},${LDAP_GROUP_DN},${LDAP_DN_BASE} memberUid | grep memberUid: | awk '{print $2}') ]] 
			then 
			echo -e "\tUser list on LDAP group is empty"
		else
			${LDAP_COMMAND_BEGIN} -b cn=${GROUP},${LDAP_GROUP_DN},${LDAP_DN_BASE} memberUid | grep memberUid: | awk '{print $2}' >> ${CONTENT_GROUP}
		fi
	fi
	if [ -f ${CONTENT_GROUP} ] && [[ ! -z $(cat ${CONTENT_GROUP}) ]]
		then
		cat ${CONTENT_GROUP} >> ${LIST_USERS}
		GROUP_FULL_NAME=""
		if [[ ${LDAP_GROUP_OBJECTCLASS} = "posixGroup" ]] && [[ ! -z $(${LDAP_COMMAND_BEGIN} -b cn=${GROUP},${LDAP_GROUP_DN},${LDAP_DN_BASE} apple-group-realname | grep apple-group-realname: ) ]]
			then
			GROUP_FULL_NAME=$(${LDAP_COMMAND_BEGIN} -b cn=${GROUP},${LDAP_GROUP_DN},${LDAP_DN_BASE} apple-group-realname | grep apple-group-realname: | awk 'sub( "^......................", "")')
			echo "   ...Group full name: ${GROUP_FULL_NAME}"
		fi
		for CONTENT_GROUP_USER in $(cat ${CONTENT_GROUP})
		do
			echo "${CONTENT_GROUP_USER} ${GROUP} $(echo ${GROUP_FULL_NAME} | perl -p -e 's/ /%%%/g')" >> ${LIST_GROUP_MEMBERS}
		done
	fi
	rm ${CONTENT_GROUP}
	done
fi

# Remove duplicate users in list
awk '!x[$0]++' ${LIST_USERS} > ${LIST_USERS_CLEAN} 
echo -e "\nThe following users will be exported:"
cat ${LIST_USERS_CLEAN} | perl -p -e 's/\n/ - /g' | awk 'sub( "...$", "" )'

# Verification if there is some users 
[[ -z $(cat ${LIST_USERS_CLEAN}) ]] && error "No user were found. Export aborded!"

for USER in $(cat ${LIST_USERS_CLEAN})
do
	CONTENT_USER=$(mktemp /tmp/LDAP2vCard_user_content.XXXXX)
	${LDAP_COMMAND_BEGIN} -b ${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} -x uid=${USER} uid uidNumber givenName sn cn apple-company departmentNumber title street postalCode l c telephoneNumber facsimileTelephoneNumber homePhone mobile pager apple-imhandle mail > ${CONTENT_USER}
	[ $? -ne 0 ] && echo -e "Error while exporting user ${USER}. Please verify vCard result."
	OLDIFS=$IFS; IFS=$'\n'
	for LINE in $(cat ${CONTENT_USER})
	do
		base64decode $LINE >> ${DIR_TEMP_USERS}/${USER}
	done
	IFS=$OLDIFS
	rm ${CONTENT_USER}
done

# Add group informations
if [[ ${GROUP_LIMIT} != "0" ]]
	then
	cat ${LIST_GROUP_MEMBERS} | \
	while read UID_USER GROUP_USER GROUP_FN
	do
		[[ -z ${UID_USER} ]] && [[ -z ${GROUP_USER} ]] && continue
		[[ -z ${GROUP_FN} ]] && echo "memberOf: ${GROUP_USER}" >> ${DIR_TEMP_USERS}/${UID_USER}
		[[ ! -z ${GROUP_FN} ]] && echo "memberOf: $(echo ${GROUP_FN} | perl -p -e 's/%%%/ /g')" >> ${DIR_TEMP_USERS}/${UID_USER}		
	done < ${LIST_GROUP_MEMBERS}
fi

# Create vCard v3 
[[ -f ${PATH_EXPORT_VCARD}/${DATANAME} ]] && mv ${PATH_EXPORT_VCARD}/${DATANAME} ${PATH_EXPORT_VCARD}/${DATANAME}.old
for FILE in $(find ${DIR_TEMP_USERS} -type f -maxdepth 1)
do
	FIRST_NAME=$(cat ${FILE} | grep ^givenName: | perl -p -e 's/givenName: //g')
	NAME=$(cat ${FILE} | grep ^sn: | perl -p -e 's/sn: //g')
	FULL_NAME=$(cat ${FILE} | grep ^cn: | perl -p -e 's/cn: //g')
	ORGANIZATION=$(cat ${FILE} | grep ^apple-company: | perl -p -e 's/apple-company: //g')
	TITLE=$(cat ${FILE} | grep ^title: | perl -p -e 's/title: //g')
	ADR="$(cat ${FILE} | grep ^street: | perl -p -e 's/street: //g');$(cat ${FILE} | grep ^l: | perl -p -e 's/l: //g');;$(cat ${FILE} | grep postalCode: | perl -p -e 's/postalCode: //g');$(cat ${FILE} | grep c: | perl -p -e 's/c: //g')"
	UID_VCARD="ldap2vcard-$(cat ${FILE} | grep ^uid: | perl -p -e 's/uid: //g')-$(cat ${FILE} | grep uidNumber: | perl -p -e 's/uidNumber: //g')"
	ROLE=$(cat ${FILE} | grep ^apple-departmentNumber: | perl -p -e 's/departmentNumber: //g')
	IM_AIM=$(cat ${FILE} | grep '^apple-imhandle: AIM:' | perl -p -e 's/apple-imhandle: AIM://g')
	IM_MSN=$(cat ${FILE} | grep '^apple-imhandle: MSN:' | perl -p -e 's/apple-imhandle: MSN://g')
	IM_ICQ=$(cat ${FILE} | grep '^apple-imhandle: ICQ:' | perl -p -e 's/apple-imhandle: ICQ://g')
	IM_JABBER=$(cat ${FILE} | grep '^apple-imhandle: Jabber:' | perl -p -e 's/apple-imhandle: Jabber://g')
	IM_YAHOO=$(cat ${FILE} | grep '^apple-imhandle: Yahoo:' | perl -p -e 's/apple-imhandle: Yahoo://g')
	
	# Begining vCard
	echo "BEGIN:VCARD" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "VERSION:3.0" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "N;ENCODING=8BIT;CHARSET=UTF-8:${NAME};${FIRST_NAME}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "FN;ENCODING=8BIT;CHARSET=UTF-8:${FULL_NAME}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "ORG;ENCODING=8BIT;CHARSET=UTF-8:${ORGANIZATION}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "TITLE;ENCODING=8BIT;CHARSET=UTF-8:${TITLE}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "ADR;TYPE=WORK;ENCODING=8BIT;CHARSET=UTF-8:;;${ADR}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "ROLE;ENCODING=8BIT;CHARSET=UTF-8:${ROLE}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	# Processing emails
	LIST_EMAILS_ADDRESS=$(mktemp /tmp/LDAP2vCard_list_emails_addresses.XXXXX)
	SECONDARY_EMAILS=$(mktemp /tmp/LDAP2vCard_list_sec_emails_addresses.XXXXX)
	cat ${FILE} | grep ^mail: | perl -p -e 's/mail: //g' >> ${LIST_EMAILS_ADDRESS}
	LINES_NUMBER=$(cat ${LIST_EMAILS_ADDRESS} | grep "." | wc -l)
    if [[ ! -z ${LIST_EMAILS_ADDRESS} ]] && [ $LINES_NUMBER -eq 1 ]
    	then
    	PRINCIPAL_EMAIL=$(head -n 1 ${LIST_EMAILS_ADDRESS})
    	echo "EMAIL;type=INTERNET;TYPE=PREF;ENCODING=8BIT;CHARSET=UTF-8:${PRINCIPAL_EMAIL}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	elif [[ ! -z ${LIST_EMAILS_ADDRESS} ]] && [ $LINES_NUMBER -gt 1 ]
    	then
    	if [[ -z ${MAIN_DOMAIN} ]]
    		then
    		PRINCIPAL_EMAIL=$(head -n 1 ${LIST_EMAILS_ADDRESS})
	    	echo "EMAIL;type=INTERNET;TYPE=PREF;ENCODING=8BIT;CHARSET=UTF-8:${PRINCIPAL_EMAIL}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	    else
	    	cat ${LIST_EMAILS_ADDRESS} | grep ${MAIN_DOMAIN} > /dev/null 2>&1
	    	if [ $? -ne 0 ]
	    		then
	    		PRINCIPAL_EMAIL=$(head -n 1 ${LIST_EMAILS_ADDRESS})
	    		echo "EMAIL;type=INTERNET;TYPE=PREF;ENCODING=8BIT;CHARSET=UTF-8:${PRINCIPAL_EMAIL}" >> ${PATH_EXPORT_VCARD}/${DATANAME}		
	    	else
	    		PRINCIPAL_EMAIL=$(cat ${LIST_EMAILS_ADDRESS} | grep ${MAIN_DOMAIN} | head -n 1)
	    		echo "EMAIL;type=INTERNET;TYPE=PREF;ENCODING=8BIT;CHARSET=UTF-8:${PRINCIPAL_EMAIL}" >> ${PATH_EXPORT_VCARD}/${DATANAME}		
	    	fi
	    fi
	    cat ${LIST_EMAILS_ADDRESS} | grep -v ${PRINCIPAL_EMAIL} >> ${SECONDARY_EMAILS}
		for SEC_EMAIL in $(cat ${SECONDARY_EMAILS})
		do
			echo "EMAIL;type=INTERNET;ENCODING=8BIT;CHARSET=UTF-8:${SEC_EMAIL}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
		done
    fi
    rm ${LIST_EMAILS_ADDRESS}
    rm ${SECONDARY_EMAILS}
    # Processing phone numbers
	OLDIFS=$IFS; IFS=$'\n'
	for telephoneNumber in $(cat ${FILE} | grep ^telephoneNumber: | perl -p -e 's/telephoneNumber: //g')
	do
		echo "TEL;TYPE=VOICE;TYPE=WORK;ENCODING=8BIT;CHARSET=UTF-8:${telephoneNumber}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	done
	for facsimileTelephoneNumber in $(cat ${FILE} | grep ^facsimileTelephoneNumber: | perl -p -e 's/facsimileTelephoneNumber: //g')
	do
		echo "TEL;TYPE=FAX;TYPE=WORK;ENCODING=8BIT;CHARSET=UTF-8:${facsimileTelephoneNumber}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	done
	for homePhone in $(cat ${FILE} | grep ^homePhone: | perl -p -e 's/homePhone: //g')
	do
		echo "TEL;TYPE=VOICE;TYPE=HOME;ENCODING=8BIT;CHARSET=UTF-8:${homePhone}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	done
	for mobile in $(cat ${FILE} | grep ^mobile: | perl -p -e 's/mobile: //g')
	do
		echo "TEL;TYPE=CELL;TYPE=HOME;ENCODING=8BIT;CHARSET=UTF-8:${mobile}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	done
	for pager in $(cat ${FILE} | grep ^pager: | perl -p -e 's/pager: //g')
	do
		echo "TEL;TYPE=PAGER;TYPE=WORK;ENCODING=8BIT;CHARSET=UTF-8:${pager}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	done
	# Processing categories
	CATEGORIES=$(cat ${FILE} | grep '^memberOf' | perl -p -e 's/memberOf: //g' | perl -p -e 's/\n/,/g')
	[[ ! -z ${CATEGORIES} ]] && echo "CATEGORIES;ENCODING=8BIT;CHARSET=UTF-8:$(echo ${CATEGORIES} | awk 'sub( ".$", "" )')" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	IFS=$OLDIFS
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=aim:aim;CHARSET=UTF-8:${IM_AIM}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=icq:icq;CHARSET=UTF-8:${IM_ICQ}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=jabber:xmpp;CHARSET=UTF-8:${IM_JABBER}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=msn:msn;CHARSET=UTF-8:${IM_MSN}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=yahoo:ymsgr;CHARSET=UTF-8:${IM_YAHOO}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=sip:sip;CHARSET=UTF-8:" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=twitter:twitter;CHARSET=UTF-8:" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=googletalk:xmpp;CHARSET=UTF-8:" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=xmpp:xmpp;CHARSET=UTF-8:" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=facebook:xmpp;CHARSET=UTF-8:" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=skype:skype;CHARSET=UTF-8:" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=qq:x-apple;CHARSET=UTF-8:" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "IMPP;ENCODING=8BIT;X-SERVICE-TYPE=gadugadu:x-apple;CHARSET=UTF-8:" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "REV:$(date +"%Y%m%dT%H%M%SZ")" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "X-ABUID:ABPerson" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "KIND:organization" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	# echo "NOTE;ENCODING=8BIT;CHARSET=UTF-8:Export made on ${HOSTNAME}\nwith ${VERSION}\n\n`date +"%Y-%m-%d-%H:%M:%S"`" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "UID:${UID_VCARD}" >> ${PATH_EXPORT_VCARD}/${DATANAME}
	echo "END:VCARD" >> ${PATH_EXPORT_VCARD}/${DATANAME}
done

echo ""
echo "********************************* ${SCRIPT_NAME} finished *********************************"
alldone 0