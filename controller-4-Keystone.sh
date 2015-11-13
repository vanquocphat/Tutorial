#!/bin/bash -ex
#

source config.cfg

apt-get -y install keystone python-keystoneclient 

filekeystone=/etc/keystone/keystone.conf

cat << EOF > $filekeystone
[DEFAULT]
verbose = True
log_dir=/var/log/keystone
admin_token = $TOKEN_PASS

[assignment]
[auth]
[cache]
[catalog]
[credential]

[database]
connection = mysql://keystone:$KEYSTONE_DBPASS@$CON_MGNT_IP/keystone

[ec2]
[endpoint_filter]
[endpoint_policy]
[federation]
[identity]
[identity_mapping]
[kvs]
[ldap]
[matchmaker_redis]
[matchmaker_ring]
[memcache]
[oauth1]
[os_inherit]
[paste_deploy]
[policy]
[revoke]
[saml]
[signing]
[ssl]
[stats]
[token]
provider = keystone.token.providers.uuid.Provider
driver = keystone.token.persistence.backends.sql.Token

[trust]
[extra_headers]
Distribution = Ubuntu

EOF

#
rm  /var/lib/keystone/keystone.db

service keystone restart
sleep 3
service keystone restart
sleep 3
keystone-manage db_sync

(crontab -l -u keystone 2>&1 | grep -q token_flush) || \
echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' >> /var/spool/cron/crontabs/keystone
sleep 5

########################################

export OS_SERVICE_TOKEN="$TOKEN_PASS"
export OS_SERVICE_ENDPOINT="http://$CON_MGNT_IP:35357/v2.0"
export SERVICE_ENDPOINT="http://$CON_MGNT_IP:35357/v2.0"

get_id () {
    echo `$@ | awk '/ id / { print $4 }'`
}

echo "#Begin configuring tenants, users and roles in Keystone "
# Tenants
ADMIN_TENANT=$(get_id keystone tenant-create --name=$ADMIN_TENANT_NAME)
SERVICE_TENANT=$(get_id keystone tenant-create --name=$SERVICE_TENANT_NAME)
DEMO_TENANT=$(get_id keystone tenant-create --name=$DEMO_TENANT_NAME)
INVIS_TENANT=$(get_id keystone tenant-create --name=$INVIS_TENANT_NAME)

# Users
ADMIN_USER=$(get_id keystone user-create --name="$ADMIN_USER_NAME" --pass="$ADMIN_PASS" --email=phatvq@openstack.com)
DEMO_USER=$(get_id keystone user-create --name="$DEMO_USER_NAME" --pass="$ADMIN_PASS" --email=phatvq@openstack.com)

# Roles
ADMIN_ROLE=$(get_id keystone role-create --name="$ADMIN_ROLE_NAME")
KEYSTONEADMIN_ROLE=$(get_id keystone role-create --name="$KEYSTONEADMIN_ROLE_NAME")
KEYSTONESERVICE_ROLE=$(get_id keystone role-create --name="$KEYSTONESERVICE_ROLE_NAME")

# Add Roles to Users in Tenants
keystone user-role-add --user-id $ADMIN_USER --role-id $ADMIN_ROLE --tenant-id $ADMIN_TENANT
keystone user-role-add --user-id $ADMIN_USER --role-id $ADMIN_ROLE --tenant-id $DEMO_TENANT
keystone user-role-add --user-id $ADMIN_USER --role-id $KEYSTONEADMIN_ROLE --tenant-id $ADMIN_TENANT
keystone user-role-add --user-id $ADMIN_USER --role-id $KEYSTONESERVICE_ROLE --tenant-id $ADMIN_TENANT

# The Member role is used by Horizon and Swift
MEMBER_ROLE=$(get_id keystone role-create --name="$MEMBER_ROLE_NAME")
keystone user-role-add --user-id $DEMO_USER --role-id $MEMBER_ROLE --tenant-id $DEMO_TENANT
keystone user-role-add --user-id $DEMO_USER --role-id $MEMBER_ROLE --tenant-id $INVIS_TENANT

# Configure service users/roles
NOVA_USER=$(get_id keystone user-create --name=nova --pass="$SERVICE_PASSWORD" --tenant-id $SERVICE_TENANT --email=nova@openstack.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $NOVA_USER --role-id $ADMIN_ROLE

GLANCE_USER=$(get_id keystone user-create --name=glance --pass="$SERVICE_PASSWORD" --tenant-id $SERVICE_TENANT --email=glance@openstack.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $GLANCE_USER --role-id $ADMIN_ROLE

SWIFT_USER=$(get_id keystone user-create --name=swift --pass="$SERVICE_PASSWORD" --tenant-id $SERVICE_TENANT --email=swift@openstack.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $SWIFT_USER --role-id $ADMIN_ROLE

RESELLER_ROLE=$(get_id keystone role-create --name=ResellerAdmin)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $NOVA_USER --role-id $RESELLER_ROLE

NEUTRON_USER=$(get_id keystone user-create --name=neutron --pass="$SERVICE_PASSWORD" --tenant-id $SERVICE_TENANT --email=neutron@openstack.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $NEUTRON_USER --role-id $ADMIN_ROLE

CINDER_USER=$(get_id keystone user-create --name=cinder --pass="$SERVICE_PASSWORD" --tenant-id $SERVICE_TENANT --email=cinder@openstack.com)
keystone user-role-add --tenant-id $SERVICE_TENANT --user-id $CINDER_USER --role-id $ADMIN_ROLE

sleep 5 

#API Endpoint
keystone service-create --name=keystone --type=identity --description="OpenStack Identity"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ identity / {print $2}') \
--publicurl=http://$CON_MGNT_IP:5000/v2.0 \
--internalurl=http://$CON_MGNT_IP:5000/v2.0 \
--adminurl=http://$CON_MGNT_IP:35357/v2.0

keystone service-create --name=glance --type=image --description="OpenStack Image Service"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ image / {print $2}') \
--publicurl=http://$CON_MGNT_IP:9292 \
--internalurl=http://$CON_MGNT_IP:9292 \
--adminurl=http://$CON_MGNT_IP:9292

keystone service-create --name=nova --type=compute --description="OpenStack Compute"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ compute / {print $2}') \
--publicurl=http://$CON_MGNT_IP:8774/v2/%\(tenant_id\)s \
--internalurl=http://$CON_MGNT_IP:8774/v2/%\(tenant_id\)s \
--adminurl=http://$CON_MGNT_IP:8774/v2/%\(tenant_id\)s

keystone service-create --name neutron --type network --description "OpenStack Networking"
keystone endpoint-create \
--service-id $(keystone service-list | awk '/ network / {print $2}') --publicurl http://$CON_MGNT_IP:9696 \
--adminurl http://$CON_MGNT_IP:9696 \
--internalurl http://$CON_MGNT_IP:9696

keystone service-create --name=cinder --type=volume --description="OpenStack Block Storage"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ volume / {print $2}') \
--publicurl=http://$CON_MGNT_IP:8776/v1/%\(tenant_id\)s \
--internalurl=http://$CON_MGNT_IP:8776/v1/%\(tenant_id\)s \
--adminurl=http://$CON_MGNT_IP:8776/v1/%\(tenant_id\)s

keystone service-create --name=cinderv2 --type=volumev2 --description="OpenStack Block Storage v2"
keystone endpoint-create \
--service-id=$(keystone service-list | awk '/ volumev2 / {print $2}') \
--publicurl=http://$CON_MGNT_IP:8776/v2/%\(tenant_id\)s \
--internalurl=http://$CON_MGNT_IP:8776/v2/%\(tenant_id\)s \
--adminurl=http://$CON_MGNT_IP:8776/v2/%\(tenant_id\)s

keystone service-create --name=swift --type=object-store --description="OpenStack Object Storage"
keystone endpoint-create --service-id=$(keystone service-list | awk '/ object-store / {print $2}') --publicurl='http://10.10.10.71:8080/v1/AUTH_%(tenant_id)s' --internalurl='http://10.10.10.71:8080/v1/AUTH_%(tenant_id)s' --adminurl=http://10.10.10.71:8080

echo "########## Creating environment script ##########"
sleep 5
echo "export OS_PROJECT_DOMAIN_ID=default" >> admin-openrc.sh
echo "export OS_USER_DOMAIN_ID=default" >> admin-openrc.sh
echo "export OS_USERNAME=admin" >> admin-openrc.sh
echo "export OS_PASSWORD=$ADMIN_PASS" >> admin-openrc.sh
echo "export OS_TENANT_NAME=admin" >> admin-openrc.sh
echo "export OS_AUTH_URL=http://$CON_MGNT_IP:35357/v2.0" >> admin-openrc.sh
echo "export OS_VOLUME_API_VERSION=2" >> admin-openrc.sh

echo "########## Unset previous environment variable ##########"
unset OS_SERVICE_TOKEN OS_SERVICE_ENDPOINT
chmod +x admin-openrc.sh

sleep 5
echo "########## Execute environment script ##########"
source admin-openrc.sh
sleep 5
keystone user-list
sleep 5
echo "Finish setup keystone#"






