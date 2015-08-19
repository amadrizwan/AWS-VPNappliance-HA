#!/bin/sh
# This script will monitor both VPN instances and swap routes
# if communication with the other instance fails

# VPN instance variables
# Other instance's IP to ping and route to grab if other node goes down
EIP=
VPN1_ID=
VPN2_ID=
RT_ID=
REMOTE_RANGE=


# Specify the EC2 region that this will be running in (e.g. https://ec2.us-east-1.amazonaws.com)
EC2_URL=

# Health Check variables
Num_Pings=3
Ping_Timeout=1
Wait_Between_Pings=1
Wait_for_Instance_Stop=60
Wait_for_Instance_Start=300

# Who has route VPN1 or 2
WHO_HAS_RT="VPN1"

# Run aws-apitools-common.sh to set up default environment variables and to
# leverage AWS security credentials provided by EC2 roles
. /etc/profile.d/aws-apitools-common.sh

# Determine the VPN instances private IP so we can ping the both instance, swap
# its route, and reboot it. Requires EC2 DescribeInstances, ReplaceRoute, and Start/RebootInstances
# permissions. The following example EC2 Roles policy will authorize these commands:
# {
# "Statement": [
# {
# "Action": [
# "ec2:DescribeInstances",
# "ec2:CreateRoute",
# "ec2:ReplaceRoute",
# "ec2:StartInstances",
# "ec2:StopInstances"
# ],
# "Effect": "Allow",
# "Resource": "*"
# }
# ]
# }

# Get VPN1 instance's IP
VPN1_IP=`/opt/aws/bin/ec2-describe-instances $VPN1_ID -U $EC2_URL | grep PRIVATEIPADDRESS -m 1 | awk '{print $2;}'`
# Get VPN2 instance's IP
VPN2_IP=`/opt/aws/bin/ec2-describe-instances $VPN2_ID -U $EC2_URL | grep PRIVATEIPADDRESS -m 1 | awk '{print $2;}'`

# Get ENI ID of VPN1 eth0
ENI_VPN1=`/opt/aws/bin/ec2-describe-instances $VPN1_ID -U $EC2_URL | grep NIC -m 1 | awk  '{print $2;}'`
# Get ENI ID of VPN2 eth0
ENI_VPN2=`/opt/aws/bin/ec2-describe-instances $VPN2_ID -U $EC2_URL | grep NIC -m 1 | awk  '{print $2;}'`

# Get alloc ID for EIP
EIP_ALLOC=`/opt/aws/bin/ec2-describe-addresses -U $EC2_URL | grep $EIP | awk  '{print $5;}'`

########################  Starting Script #######################

echo `date` "-- Starting VPN monitor"
echo `date` "-- Assigning EIP to VPN1 ENI-1"
/opt/aws/bin/ec2-associate-address -a $EIP_ALLOC -n $ENI_VPN1  --allow-reassociation -U $EC2_URL
echo `date` "-- Adding VPN1 instance to $RT_ID default on start"
/opt/aws/bin/ec2-replace-route $RT_ID -r $REMOTE_RANGE -n $ENI_VPN1 -U $EC2_URL
# If replace-route failed, then the route might not exist and may need to be created instead
if [ "$?" != "0" ]; then
 /opt/aws/bin/ec2-create-route $RT_ID -r $REMOTE_RANGE -n $ENI_VPN1 -U $EC2_URL
fi


while [ . ]; do
 # Check health of VPN1 instance
 pingresult_VPN1=`ping -c $Num_Pings -W $Ping_Timeout $VPN1_IP | grep time= | wc -l`
 # Check to see if any of the health checks succeeded, if not
 if [ "$pingresult_VPN1" == "0" ]; then
 # Set HEALTHY variables to unhealthy (0)
 VPN1_HEALTHY=0
 STOPPING_VPN1=0
 while [ "$VPN1_HEALTHY" == "0" ]; do
 # VPN1 instance is unhealthy, loop while we try to fix it
 if [ "$WHO_HAS_RT" == "VPN1" ]; then
 echo `date` "-- VPN1 heartbeat failed, assigning EIP to VPN2 instance ENI-1"
/opt/aws/bin/ec2-associate-address -a $EIP_ALLOC -n $ENI_VPN2 --allow-reassociation -U $EC2_URL
 echo `date` "-- VPN1 heartbeat failed, VPN2 instance taking over $LB_RT_ID and $NODE_RT_ID routes"
/opt/aws/bin/ec2-replace-route $RT_ID -r $REMOTE_RANGE -n $ENI_VPN2 -U $EC2_URL

        WHO_HAS_RT="VPN2"
 fi
 # Check VPN1 state to see if we should stop it or start it again
 VPN1_STATE=`/opt/aws/bin/ec2-describe-instances $VPN1_ID -U $EC2_URL | grep INSTANCE | awk '{print $5;}'`
 if [ "$VPN1_STATE" == "stopped" ]; then
 echo `date` "-- VPN1 instance stopped, starting it back up"
 /opt/aws/bin/ec2-start-instances $VPN1_ID -U $EC2_URL
        VPN1_HEALTHY=1
 sleep $Wait_for_Instance_Start
 else
        if [ "$STOPPING_VPN1" == "0" ]; then
 echo `date` "-- VPN1 instance $VPN1_STATE, attempting to stop for reboot"
        /opt/aws/bin/ec2-stop-instances $VPN1_ID -U $EC2_URL
        STOPPING_VPN1=1
        fi
 sleep $Wait_for_Instance_Stop
 fi
 done
#else
fi

# Check health of VPN2 instance
 pingresult_VPN2=`ping -c $Num_Pings -W $Ping_Timeout $VPN2_IP | grep time= | wc -l`
 # Check to see if any of the health checks succeeded, if not
 if [ "$pingresult_VPN2" == "0" ]; then
 # Set HEALTHY variables to unhealthy (0)
 VPN2_HEALTHY=0
 STOPPING_VPN2=0
 while [ "$VPN2_HEALTHY" == "0" ]; do
 # VPN2 instance is unhealthy, loop while we try to fix it
 if [ "$WHO_HAS_RT" == "VPN2" ]; then
 echo `date` "-- VPN2 heartbeat failed, assigning EIP to VPN1 instance ENI-1"
/opt/aws/bin/ec2-associate-address -a $EIP_ALLOC -n $ENI_VPN1 --allow-reassociation -U $EC2_URL
 echo `date` "-- VPN2 heartbeat failed, VPN1 instance taking over $LB_RT_ID and $NODE_RT_ID routes"
/opt/aws/bin/ec2-replace-route $NODE_RT_ID -r $REMOTE_RANGE -n $ENI_VPN1 -U $EC2_URL
        WHO_HAS_RT="VPN1"
 fi
 # Check VPN2 state to see if we should stop it or start it again
 VPN2_STATE=`/opt/aws/bin/ec2-describe-instances $VPN2_ID -U $EC2_URL | grep INSTANCE | awk '{print $5;}'`
 if [ "$VPN2_STATE" == "stopped" ]; then
 echo `date` "-- VPN2 instance stopped, starting it back up"
 /opt/aws/bin/ec2-start-instances $VPN2_ID -U $EC2_URL
        VPN2_HEALTHY=1
 sleep $Wait_for_Instance_Start
 else
        if [ "$STOPPING_VPN2" == "0" ]; then
 echo `date` "-- VPN2 instance $VPN2_STATE, attempting to stop for reboot"
        /opt/aws/bin/ec2-stop-instances $VPN2_ID -U $EC2_URL
        STOPPING_VPN2=1
        fi
 sleep $Wait_for_Instance_Stop
 fi
 done


 else
 sleep $Wait_Between_Pings
 fi
done
