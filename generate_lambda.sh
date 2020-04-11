# CONST
RED='\033[0;31m'
PURPLE='\033[0;35m'
YELLOW='\033[0;33m'
NORMAL='\033[0m' # No Color
# paths
selenium_lib_path=./layers/selenium-binaries
python_dep_path=./layers/python-dependencies
# VAR
selenium_version="3.141.0"
app_name=""
app_name_dash=""
app_name_camelcase=""

main()
{
    check_params "$@"

    create_lambda_template

    get_dependencies

    build

    deploy

    # enable the next line if you want to automatically start the Docker enviroment
    # start_docker_env
}

function check_params()
{
    if [ $# -ne 1 ]; then
        echo -e "${RED}ERROR: lambda function name is required (alphanumeric, - and _ allowed) ${NORMAL}"
        exit -1
    fi

    app_name=$1

    if [[ "${app_name}" =~ [^a-zA-Z0-9_-] ]]; then
        echo -e "${RED}ERROR: parameter [lambda function name] can only contains alphanumerics, numbers, - and _${NORMAL}"
        exit -1
    fi

    if [[ -d "$app_name" ]]
    then
        echo -e "${RED}ERROR: lambda function with name $app_name already exist in this folder${NORMAL}"
        exit -1
    fi  
}

function create_lambda_template()
{
    echo -e "\n${PURPLE}creating lambda template with command: sam init${NORMAL}"
    echo -e "${PURPLE}the settings will be automatically managed by the script generate_lambda.sh${NORMAL}"
    
    # the next instruction will automatically answer the question asked by the command 'sam init'
    printf "%s\n" 1 9 $app_name 1 | sam init || exit_on_error "sam init"
    
    cd ./"$app_name"

    # overwrite the default template with the new one that includes the changes for selenium
    echo "overwriting default yaml template"
    set_template_scraper
    echo "$template_no_scraper" > template.yaml

    # rename app main folder
    mv "hello_world" $app_name
}

function get_dependencies()
{
    echo -e "\n${PURPLE}getting dependencies${NORMAL}"
    
    echo "downloading chrome driver and headless_chromium"
    download_chromedriver_and_headless_chromium
    
    echo "installing python dependencies"
    create_python_requirements_file
    install_python_dependencies
}

function build()
{
    echo -e "\n${PURPLE}building lambda function with command: sam build -u${NORMAL}"
    sam build -u || exit_on_error "sam build -u"
}

function deploy()
{
    echo -e "\n${PURPLE}deploying lambda to AWS with command: sam deploy --guided${NORMAL}"
    echo -e "${PURPLE}the settings will be automatically managed by the script generate_lambda.sh${NORMAL}"
    
    # app_name, 2 enters and 4 yes
    set_app_name_no_underscores
    printf "${app_name_dash}\n\ny\ny\ny\ny\n" | sam deploy --guided || exit_on_error "sam deploy --guided"
}

function start_docker_env()
{
    echo -e "\n${PURPLE}starting docker local env with command: sam local start-api${NORMAL}"
    sam local start-api || exit_on_error "sam local start-api"
}

function create_python_requirements_file()
{
    file_content=$"selenium==$selenium_version\nchromedriver-binary==2.37.0\nrequests" 
    echo -e $file_content > ./requirements.txt
}

function download_chromedriver_and_headless_chromium() 
{
    # remove previous driver and binary (empty folder selenium-binaries)
    rm -r -f $selenium_lib_path/

    # create folder if not present
    mkdir -p $selenium_lib_path/
    
    # download and unzip driver and binary
    curl -SL https://chromedriver.storage.googleapis.com/2.37/chromedriver_linux64.zip > $selenium_lib_path/chromedriver.zip
    unzip $selenium_lib_path/chromedriver.zip -d $selenium_lib_path/
    rm $selenium_lib_path/chromedriver.zip
    
    curl -SL https://github.com/adieuadieu/serverless-chrome/releases/download/v1.0.0-41/stable-headless-chromium-amazonlinux-2017-03.zip > $selenium_lib_path/headless-chromium.zip
    unzip $selenium_lib_path/headless-chromium.zip -d $selenium_lib_path/
    rm $selenium_lib_path/headless-chromium.zip
}

function install_python_dependencies()
{
    rm -r -f ${python_dep_path}/
    mkdir -p ${python_dep_path}/python/lib/python3.6/site-packages

    echo -e "${YELLOW}password required to install python libs with pip${NORMAL}"
    sudo -H pip install -r requirements.txt -t ${python_dep_path}/python/lib/python3.6/site-packages    
}

function set_app_name_no_underscores()
{
    # replace all the underscores and spaces with dash (this avoid having _ and spaces in the URL)
    app_name_dash=${app_name//_/-}
}

function set_app_name_only_alphanumeric_first_W_letter_capitalized()
{
    # remove all the underscores, dashes and spaces and convert the string in camel case (same functions name style as the AWS hello world example)
    # replace - and _ with spaces
    app_name_camelcase=( ${app_name//[-_]/' '} )
    #capitalize first letter of every word
    app_name_camelcase=${app_name_camelcase[*]^} 
    # remove all spaces
    app_name_camelcase=${app_name_camelcase//[ ]/''} 
}

function exit_on_error()
{
    echo -e "${RED}ERROR: creation of function $app_name failed when running sam command: $1 ${NORMAL}"
    exit -1
}

function set_template_scraper()
{
    # replace all the underscores with dash (this avoid having underscores in the URL)
    set_app_name_no_underscores
    # remove all the underscores and dashes and convert the string in camel case (same functions name style as the AWS hello world example)
    set_app_name_only_alphanumeric_first_W_letter_capitalized

    template_no_scraper="AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: >
  ${app_name}

  Sample SAM Template for ${app_name}

Globals:
  Function:
    Timeout: 3

Resources:
  DeploymentPermission:
    Type: \"AWS::Lambda::LayerVersionPermission\"
    Properties:
      Action: lambda:GetLayerVersion
      LayerVersionArn: !Ref ChromiumLayer
      Principal: '*'

  DeploymentPermission:
    Type: \"AWS::Lambda::LayerVersionPermission\"
    Properties:
      Action: lambda:GetLayerVersion
      LayerVersionArn: !Ref PythonDepLayer
      Principal: '*'

  ChromiumLayer:
    Type: AWS::Serverless::LayerVersion
    Properties:
      LayerName: chromium-selenium-layer
      Description: Headless Chromium and Selenium WebDriver
      ContentUri: ${selenium_lib_path}
      CompatibleRuntimes:
        - nodejs8.10
        - python3.8
        - python2.7
        - go1.x
        - java8
      LicenseInfo: 'MIT'
      RetentionPolicy: Retain

  PythonDepLayer:
    Type: AWS::Serverless::LayerVersion
    Properties:
      LayerName: selenium-layer
      Description: Selenium, Requests, Chromedriver-binary
      ContentUri: ${python_dep_path}
      CompatibleRuntimes:
        - python3.7
      LicenseInfo: 'MIT'
      RetentionPolicy: Retain

  ${app_name_camelcase}Function:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: ${app_name}/
      Handler: app.lambda_handler
      Runtime: python3.6
      Events:
        ${app_name_camelcase}:
          Type: Api # More info about API Event Source: https://github.com/awslabs/serverless-application-model/blob/master/versions/2016-10-31.md#api
          Properties:
            Path: /${app_name_dash}
            Method: get
      MemorySize: 764
      Timeout: 300
      Layers:
        - !Ref ChromiumLayer
        - !Ref PythonDepLayer
      Environment:
        Variables:
          CLEAR_TMP: \"true\"
          PATH: /var/lang/bin:/usr/local/bin:/usr/bin/:/bin:/opt/bin:/tmp/bin:/tmp/bin/lib

Outputs:
  ${app_name_camelcase}Api:
    Description: \"API Gateway endpoint URL for Prod stage for ${app_name} function\"
    Value: !Sub \"https://\${ServerlessRestApi}.execute-api.\${AWS::Region}.amazonaws.com/Prod/${app_name_dash}/\"
  ${app_name_camelcase}Function:
    Description: \"${app_name} Lambda Function ARN\"
    Value: !GetAtt ${app_name_camelcase}Function.Arn
  ${app_name_camelcase}FunctionIamRole:
    Description: \"Implicit IAM Role created for ${app_name} function\"
    Value: !GetAtt ${app_name_camelcase}FunctionRole.Arn"
}

main "$@" # by passing "$@" to main() you can access the command-line arguments $1, $2, etc just as you normally would