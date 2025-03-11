#!/bin/bash

# ========================
# variables
# ========================
RESOURCE_GROUP_NAME=dotnetdemo
VM_NAME=dotnetdemo-vm
PORT=5000
LOCATION="northeurope"
ADMIN_USER="azureuser"
RUNTIME="8.0"

# local paths
LOCAL_APP_DIR=$(cygpath -u "C:\Users\yotak\Yotaka_portfolio\Yotaka_portfolio")
LOCAL_PUBLISH_DIR=$(cygpath -u "C:\Users\yotak\Yotaka_portfolio\Yotaka_portfolio\bin\Release\net9.0\publish")

# ========================
# step 1: Create a resource group.
# ========================
echo "Creating Azure resource group: $RESOURCE_GROUP in $LOCATION..."
az group create --name $RESOURCE_GROUP_NAME --location $LOCATION

# ========================
# step 2: Create a virtual machine.
# ========================
echo " Creating VM: $VM_NAME..."
az vm create \
  --resource-group $RESOURCE_GROUP_NAME \
  --name $VM_NAME \
  --image Ubuntu2404 \
  --size Standard_B1s \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys\
  --output none || exit 1 # exit if error gor recommend from grok ai. make sure which are you now.  
  
# ========================
# step 3: Open port 5000.
# ========================
az vm open-port \
  --resource-group $RESOURCE_GROUP_NAME \
  --name $VM_NAME \
  --port $PORT\
  --output none || exit 1

# ========================
# step 4: Get IP public address of the VM.
# ========================
echo "Getting public IP address of the VM..."
PUBLIC_IP=$(az vm show \
  --resource-group $RESOURCE_GROUP_NAME \
  --name $VM_NAME \
  --show-details \
  --query [publicIps] \
  --output tsv)\
    || exit 1

# ========================
# step 5: Publish the .net mvc app .
# ========================
echo "Publishing the .NET MVC app..."
cd "$LOCAL_APP_DIR" || { echo " ERROR: App directory not found!"; exit 1; }
dotnet publish -c Release -o "$LOCAL_PUBLISH_DIR" || { echo " ERROR: Build failed!"; exit 1; }
echo "build successful"

# ========================
# step 6: Create the directory on the VM and set permissions.
# ========================
echo "Creating directory on the VM..."
ssh -o StrictHostKeyChecking=no $ADMIN_USER@$PUBLIC_IP << EOF
    sudo mkdir -p /opt/Yotaka_portfolio
    sudo chown $ADMIN_USER:$ADMIN_USER /opt/Yotaka_portfolio
    echo "$ADMIN_USER ALL=(ALL) NOPASSWD:/bin/systemctl" | sudo tee /etc/sudoers.d/$ADMIN_USER
EOF

# ========================
# step 7: Deploy app to the vm .
# ========================
echo "Deploying the app to the VM..."
scp -r -o StrictHostKeyChecking=no "$LOCAL_PUBLISH_DIR"/* "$ADMIN_USER@$PUBLIC_IP:/opt/Yotaka_portfolio/" || { echo "Failed to deploy the app."; exit 1; }
echo "Deployment successful"

# ========================
# step 8: configure enviroment. (install .NET runtime, Set up a systemd service to run the app, Start the service)
# ========================
echo "Deploying the app to the VM..."
ssh -o StrictHostKeyChecking=no $ADMIN_USER@$PUBLIC_IP << EOF
echo "Installing .NET runtime..."
sudo apt-get update
wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# update package 
sudo apt-get update
sudo apt-get install -y dotnet-sdk-$RUNTIME
sudo apt-get install -y aspnetcore-runtime-$RUNTIME

echo "Create service file for the application..."
sudo bash -c "cat > /etc/systemd/system/Yotaka_portfolio.service << 'INNER_EOF'
    [Unit]
Description=MVC App
After=network.target

[Service]
ExecStart=/usr/bin/dotnet /opt/Yotaka_portfolio/Yotaka_portfolio.dll --urls http://0.0.0.0:$PORT
WorkingDirectory=/opt/Yotaka_portfolio
Restart=always
RestartSec=10
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
INNER_EOF"

    # Start service
    sudo systemctl enable Yotaka_portfolio.service
    sudo systemctl start Yotaka_portfolio.service
EOF
# ========================
# step 9: Final confirmation .
# ========================
echo "The app is running at http://$PUBLIC_IP:5000"