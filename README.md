# AWS-VPNappliance-HA

The input variables required for the script to work: <br />

EIP = Elastic IP address - public IP address to be used as VPN endpoint at AWS side <br />
VPN1_ID = Instance ID of VPN appliance 1 <br />
VPN2_ID = Instance ID of VPN appliance 2 <br />
RT_ID = Routing table ID - the routing table in which the specified remote CIDR has to be rerouted to healthy VPN appliance <br />
REMOTE_RANGE = remote CIDR to be rerouted in $RT_ID routing table <br />



