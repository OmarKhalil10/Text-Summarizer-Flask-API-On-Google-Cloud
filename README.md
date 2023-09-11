[![Python version](https://img.shields.io/badge/python-3.8-blue)](https://www.python.org/downloads/release/python-380/) [![Terraform 1.5.7](https://img.shields.io/badge/terraform-1.5.7-%23623CE4)](https://www.terraform.io) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)



# Deployment of a Text Summarizer Flask API to Google Cloud using Cloud Run, Terraform and GitHub Actions

The aim of this individual project is to utilize Docker to containerize a Flask API and deploy it on Google Cloud Run. Simultaneously, we intend to employ Terraform for setting up the necessary infrastructure. It is recommended to embrace an Infrastructure-as-Code (IaC) approach for provisioning your infrastructure when deploying an API in the cloud. IaC offers numerous advantages compared to manually configuring your cloud environment, such as effortless replication and the capability to ensure uniformity across different staging environments.

![banner](/docs/banner.png)


When you're preparing to deploy an API (or any other product) in the cloud, it's advisable to set up your infrastructure with the assistance of an Infrastructure-as-Code (IaC) tool. Utilizing IaC offers several benefits compared to manually configuring your cloud environment, including ease of replication and the capability to maintain uniformity across multiple staging environments. Terraform is a widely employed IaC tool, and in this tutorial, we'll demonstrate how to use [Terraform](https://www.terraform.io/) to deploy a [Flask](https://flask.palletsprojects.com/en/2.1.x/) API.

## 🛠️ Let's get started!

### 1. Building our Flask app
Before moving forward with cloud deployment, our first task is to develop an application that can be deployed. You can find the code for this application in the [main.py](https://github.com/OmarKhalil10/Text-Summarizer-Flask-API-On-Google-Cloud/blob/main/main.py) file and the associated templates in the [templates](https://github.com/OmarKhalil10/Text-Summarizer-Flask-API-On-Google-Cloud/blob/main/templates) directory.

To run the application, ensure you've created a virtual environment and installed the required dependencies.

```
python -m virtualenv vevn
```

```
source venv/Scripts/activate
```

```
pip install -r requiremnts.txt
```

Once we have created created a virtual environment and installed the required dependencies, we can test our API by running flask:

```
flask run
```

And we see the following output in our console:

```
 * Environment: production
   WARNING: This is a development server. Do not use it in a production deployment.
   Use a production WSGI server instead.
 * Debug mode: off
 * Running on http://127.0.0.1:5000 (Press CTRL+C to quit)
```

### 2. Dockerizing our Flask app

To containerize our Flask application using [Docker](https://docs.docker.com/get-docker/), please make sure that you have Docker installed and the Docker daemon running on your system. Once you've ensured that Docker is set up correctly, follow these steps:

1. Create a file named ```Dockerfile``` in your project directory.

2. Add the following contents to your Dockerfile:

```
# For more information, please refer to https://aka.ms/vscode-docker-python
FROM python:3.8-slim-buster

# Copy the source files into the container
WORKDIR /flask-docker
COPY . /flask-docker

# Install pip requirements
RUN pip3 install virtualenv
RUN python3 -m venv web-app 
RUN . web-app/bin/activate
RUN python3 -m pip install -r requirements.txt

EXPOSE 8080
ENV PORT 8080

# Define the command to be run when the container is started
CMD ["python", "main.py"]
```

When we are finished writing the Dockerfile, we can build our docker image and run this image in a Docker container with:

```
./run_docker.sh
```

Confirm that your container is running by checking its presence in the list of containers when you run the 'docker ps' command. Additionally, ensure that you can access the API by visiting 'http://localhost:8080' in your web browser.

Now that we have Dockerized our container, it is time to set up our cloud infrastructure.

### 3. Configure Cloud Storage bucket to store Terraform state
By default, Terraform saves the state locally in a `terraform.tfstate` file. However, if we want to provision our infrastructure through CI/CD we should use a backend for Terraform, so our state is stored remotely in a Cloud Storage bucket. A useful tutorial for creating this can be found [here](https://cloud.google.com/docs/terraform/resource-management/store-state).

Enable the Cloud Storage API:

```
gcloud services enable storage.googleapis.com
```

Add the following contents to `main.tf` inside `infra/backend`

```
# Enable storage API
resource "google_project_service" "storage" {
  provider           = google
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}
```

#### Configure Terraform to store state in a Cloud Storage bucket

In the following steps, you create a Cloud Storage bucket and change the backend configuration to your new bucket and your Google Cloud project.

#### Create the bucket

1. Add the following [google_storage_bucket](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) Terraform resource to a Terraform config file, such as `main.tf` inside `infra/backend`.

```
# This is used so there is some time for the activation of the API's to propagate through 
# Google Cloud before actually calling them.
resource "time_sleep" "wait_30_seconds" {
  create_duration = "30s"
  depends_on      = [google_project_service.storage]
}

// Terraform plugin for creating random IDs
resource "random_id" "instance_id" {
  byte_length = 8
}

resource "google_storage_bucket" "default" {
  name          = "bucket-tfstate-${random_id.instance_id.hex}"
  force_destroy = false
  location      = var.region
  storage_class = "STANDARD"
  versioning {
    enabled = true
  }
  depends_on = [time_sleep.wait_30_seconds]
}

output "bucket_name" {
  description = "Terraform backend bucket name"
  value       = google_storage_bucket.default.name
}
```

#### Change the backend configuration

Add the following text to a new Terraform configuration file called `backend.tf` inside `infra/backend`

```
terraform {
  backend "gcs" {
    bucket = "bucket-tfstate-f708fe1a360136f1"
    prefix = "terraform/state"
  }
}
```

### 4. Setting-up a service account

Ideally, we want to restrict individual users from making changes to the cloud infrastructure. Instead, we'll employ a [service account](https://cloud.google.com/iam/docs/service-accounts) and assign it the necessary permissions. In a subsequent phase, we can integrate the credentials of this service account into a CI/CD pipeline to trigger our deployments. However, for now, we'll create a service account and utilize it from our local machine.

Before we can commence building our infrastructure, we must create a project. You can do this by following the instructions provided by Google Cloud Platform (GCP). In this tutorial, we'll use the project name ```ml-tf-398511``` so remember to replace it with your chosen project name in the upcoming commands if you've opted for a different name. Once the project is created, navigate to "IAM & Admin" > ["Service Accounts"](https://console.cloud.google.com/iam-admin/serviceaccounts) and establish a service account named "infrastructure."

Then, proceed to "IAM & Admin" > ["IAM"](https://console.cloud.google.com/iam-admin/iam) and grant the following permissions to your service account:

1. Editor
2. Artifact Registry Administrator
3. Cloud Run Admin
4. Project IAM Admin
5. Service Usage Admin

Now that we've created a service account with the necessary permissions for provisioning our infrastructure, it's time to define our infrastructure.

### 5. Building our cloud infrastructure with Terraform

The first thing that we need to do is install Terraform by following the intructions [here](https://learn.hashicorp.com/tutorials/terraform/install-cli).

Once the installation process is finished, we create a new directory called ```infra``` and a new directory inside of it called ```main```

```
flask-app/
|-- main.py
|-- __init__.py
|-- templates/
|   |-- index.html
|   |-- ...
|-- static/
|   |-- css/
|   |   |-- style.css
|   |   |-- ...
|   |-- js/
|   |   |-- script.js
|   |   |-- ...
|-- infra/
|   |-- main/
|   |   |-- main.tf
|   |   |-- variables.tf
|   |   |-- outputs.tf
|   |   |-- ...
|-- requirements.txt
|-- Dockerfile
|-- README.md
|-- ...
```

Within ```infra/main```, we create a file called ```main.tf```, and initiate our file with the following contents:

```
terraform {
  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "4.25.0"
    }
  }
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
```

We specify the use of the `google-beta` provider and configure it with project-specific variables. The choice of `google-beta` instead of `google` is due to our intention to utilize the Artifact Registry for uploading our Docker images. As of the time of this writing, the `google_artifact_registry_repository` resource is only available in the `google-beta` provider. If you find that the warning on [this page](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) is no longer present, you can confidently switch to the regular `google` provider.

To define the variables we've created, you should create a file named `variables.tf` in the same directory with the following contents:

```
variable "project_id" {
  description = "The name of the project"
  type        = string
  default     = "ml-tf-398511"
}

variable "region" {
  description = "The default compute region"
  type        = string
  default     = "europe-west6"
}

variable "zone" {
  description = "The default compute zone"
  type        = string
  default     = "europe-west6-a"
}
```

In this context, `project_id` refers to the name of our Google Cloud Platform (GCP) project, and the specified `region` and `zones` are set to locations that are geographically close to my current location. However, you may want to choose a different region and zone based on your requirements. You can find a list of available regions and zones [here](https://cloud.google.com/compute/docs/regions-zones).

To set up and configure features like Cloud Run, it's essential to enable their corresponding APIs. While you can do this manually by navigating to the services in the GCP UI, for automation purposes, we prefer to use Terraform to enable these services. To accomplish this, add the following configuration to your `apis.tf` file:

```
# Enable IAM API
resource "google_project_service" "iam" {
  provider           = google-beta
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# Enable Artifact Registry API
resource "google_project_service" "artifactregistry" {
  provider           = google-beta
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud Run API
resource "google_project_service" "cloudrun" {
  provider           = google-beta
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud Resource Manager API
resource "google_project_service" "resourcemanager" {
  provider           = google-beta
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}
```

Enabling IAM, Artifact Registry, Cloud Run, and Cloud Resource Manager APIs is a necessary step. However, it's important to note that changes made to API enablement take some time to propagate through Google's systems. Directly calling these APIs could result in errors due to this delay. Simply using the [depends_on](https://www.terraform.io/language/meta-arguments/depends_on) meta-argument isn't sufficient because it triggers resources depending on API enablement immediately after enabling the APIs, not after the changes have fully propagated.

To address this issue, an intermediate `time_sleep` resource is employed into `apis.tf`. This resource is triggered once our APIs have been enabled. Then, we can include this `time_sleep` resource in the `depends_on` argument of other resources, ensuring they are triggered 30 seconds after the APIs have been enabled, allowing time for the changes to propagate through Google's systems.

```
# This is used so there is some time for the activation of the API's to propagate through 
# Google Cloud before actually calling them.
resource "time_sleep" "wait_30_seconds" {
  create_duration = "30s"
  depends_on = [
    google_project_service.artifactregistry,
    google_project_service.cloudrun,
    google_project_service.resourcemanager
  ]
}
```

Now that we have the APIs enabled, we can leverage them to create additional resources. Our first step is to create the Artifact Repository, which will serve as the destination for pushing our Docker images. In addition to the repository, we will also create a service account named `docker-pusher` and assign it the `roles/artifactregistry.writer` role for this specific repository. This role will grant the service account the necessary permissions to push images to the repository.

Inside `infra/main` Create a file named `container.tf` and add the following content:

```
# Create Artifact Registry Repository for Docker containers
resource "google_artifact_registry_repository" "my_docker_repo" {
  provider = google-beta

  location      = var.region
  repository_id = var.repository
  description   = "My docker repository"
  format        = "DOCKER"
  depends_on    = [time_sleep.wait_30_seconds]
}

# Create a Service Account
resource "google_service_account" "docker_pusher" {
  provider = google-beta

  account_id   = "docker-pusher"
  display_name = "Docker Container Pusher"
  depends_on   = [time_sleep.wait_30_seconds]
}

# Give Service Account permission to push to the Artifact Registry Repository
resource "google_artifact_registry_repository_iam_member" "docker_pusher_iam" {
  provider = google-beta

  location   = google_artifact_registry_repository.my_docker_repo.location
  repository = google_artifact_registry_repository.my_docker_repo.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.docker_pusher.email}"
  depends_on = [
    google_artifact_registry_repository.my_docker_repo,
    google_service_account.docker_pusher
  ]
}
```

And we add the following to `variables.tf`:

```
variable "repository" {
  description = "The name of the Artifact Registry repository to be created"
  type        = string
  default     = "docker-repository"
}
```

The last thing that we need to do is publish our image through Cloud Run. For this, we use google_cloud_run_service, and as the argument for image we pass `europe-west6-docker.pkg.dev/${var.project_id}/${var.repository}/${var.docker_image}`, so our resource will expect to find an image that we defined in variables.tf within our created Artifact Registry repository. We also pass some arguments to use containers with `8G` memory usage, and we should scale to more than one instance for depend on traffic. Lastly, we create a `noauth` policy and apply it to our newly created Cloud Run API so our API is `open to the public`, and we return the `URL` on which our API is available.

### NOTE
```
⚠️ Only add the noauth policy to your API if you want to open it to the public. If your API uses or exposes sensitive data, you should add some form of authentication to your API.
```

Inside `infra/main` Create a file named `deployment.tf` and add the following content:


```
# Deploy image to Cloud Run
resource "google_cloud_run_service" "summarize-text" {
  provider = google-beta
  count    = var.first_time ? 0 : 1
  name     = "summarize-text"
  location = var.region
  template {
    spec {
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository}/${var.docker_image}"
        resources {
          limits = {
            cpu    = "2"
            memory = "8G"
          }
        }
      }
    }
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = "1"
        "autoscaling.knative.dev/maxScale" = "20"
      }
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
  depends_on = [google_artifact_registry_repository_iam_member.docker_pusher_iam]
}

# Create a policy that allows all users to invoke the API
data "google_iam_policy" "noauth" {
  provider = google-beta
  count    = var.first_time ? 0 : 1
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

# Apply the no-authentication policy to our Cloud Run Service.
resource "google_cloud_run_service_iam_policy" "noauth" {
  count    = var.first_time ? 0 : 1
  provider = google-beta
  location = var.region
  project  = var.project_id
  service  = google_cloud_run_service.summarize-text[0].name

  policy_data = data.google_iam_policy.noauth[0].policy_data
}

output "cloud_run_instance_url" {
  value = var.first_time ? null : google_cloud_run_service.summarize-text[0].status.0.url
}
```

And we add the following to `variables.tf`:

```
variable "docker_image" {
  description = "The name of the Docker image in the Artifact Registry repository to be deployed to Cloud Run"
  type        = string
  default     = "summarizer-app"
}
```

Now that we have created our Terraform script, we can start using it to provision our infrastructure.

### 6. Provisioning our cloud infrastructure with Terraform

Previously, we set up a service account with the necessary permissions for managing our infrastructure. In the Google Cloud Platform, return to `"IAM & Admin" > "Service Accounts."` In the `"Actions"` column for your service account, click the `three dots`. Choose `"Manage Keys,"` then select `"Add Key" > "New Key."` Opt for `JSON` as the Key Type, which will prompt the download of a file to your local machine. Copy this downloaded file to the directory where you've created your `main.tf` and `variables.tf` files, and rename it to `infra_service_account.json`. Subsequently, craft a file named `.env` with the following content:


```
GOOGLE_APPLICATION_CREDENTIALS="infra_service_account.json"
```

Alternatively, you can hard-code the path to the service account into your `main.tf` file, but I recommend using environment variables. This approach is preferable because it provides greater flexibility for modifying your configuration when provisioning infrastructure through CI/CD in the future.


⚠️ Please exercise caution when dealing with service accounts. Keep your service account keys confidential and ensure they do not fall into the wrong hands. If you're using Git for this project, remember to add the key to your `.gitignore` file. For more information on best practices regarding service accounts, refer to [this link](https://cloud.google.com/iam/docs/using-secrets-manager).


Before proceeding to create our infrastructure, let's first check if our configuration is error-free. To do this, we'll begin by initializing our directory with the necessary setup.

```
terraform init
```

and then we validate our files with

```
terraform validate
```

which outputs:

```
Success! The configuration is valid.
```

Great! This means we can now create our infrastructure:

```
source .env && terraform apply
```

After about a minute, this will now return an error:

```
Error: Error waiting to create Service: resource is in failed state "Ready:False", message: Image 'europe-west6-docker.pkg.dev/ml-tf-398511/docker-repository/summarizer-app' not found.
```

This error is anticipated because we've configured our infrastructure to search for an image named `summarizer-app` within the `docker-repository` which we haven't created yet. Nevertheless, the preceding steps have executed successfully. If you navigate to the Artifact Registry in the UI, you'll see that our repository has indeed been created. This signifies that we are now prepared to push our Docker image to the repository to complete our setup.

### 7. Pushing the Docker image to Artifact Registry on Google Cloud

To facilitate the upload of our Docker image to the cloud, we must first acquire the key for the Terraform-created `docker-pusher` service account. You can locate this service account in the GCP Console under `IAM & Admin > Service Accounts.` Here, you should generate and download a service account key in `JSON` format, similar to the process we followed earlier for the infrastructure account. Rename this file to `docker_service_account.json` and save it in the same directory as `app.py` and `Dockerfile`.

Now, to execute commands in the command line with the permissions of our service account, we'll employ the [Google Cloud CLI](https://cloud.google.com/sdk/gcloud). You can find installation instructions [here](https://cloud.google.com/sdk/docs/install). Once it's installed, you can configure it with a profile named "docker-pusher" by using the following commands:

```
gcloud config configurations create docker-pusher
gcloud config set project ml-tf-398511
gcloud auth activate-service-account --key-file=docker_service_account.json
```

You can see your active and other available configurations with the command

```
gcloud config configurations list
```

After confirming that our `docker-pusher` configuration is active, we should set up `gcloud` as the credential helper for all Docker registries supported by Google. This can be achieved with the following command:

```
gcloud auth configure-docker europe-west6-docker.pkg.dev
```

Then, we tag our Docker image `summarizer-api:v1` with a tag in the form of

```
<SOURCE_IMAGE> <HOSTNAME>/<PROJECT-ID>/<repository>/<IMAGE>
```

which in our case becomes:

```
docker tag summarizer-api:v1 europe-west6-docker.pkg.dev/ml-tf-398511/docker-repository/summarizer-app
```

And we can then push that image to the Artifact Registry with:

```
docker push europe-west6-docker.pkg.dev/ml-tf-398511/docker-repository/summarizer-app
```

If this step is completed successfully, you should now be able to view your Docker image within the `docker-repository` repository in the [Artifact Registry](https://console.cloud.google.com/artifacts) section of the Google Cloud Platform.

### 8. Finishing up and Testing our API

This means we can now finalize deploying our API. Navigate to your directory containing `main.tf`, and apply your files once again:

```
source .env && terraform apply
```

This time, as our Docker image is accessible to the `google_cloud_run_service` component, we should not encounter any errors. Instead, we should observe the following output:

```
Apply complete! Resources: 2 added, 0 changed, 1 destroyed.

Outputs:

cloud_run_instance_url = "https://summarize-text-ltnijdawbq-oa.a.run.app"
```


Click the provided link or copy and paste the URL into your browser, and you should be greeted with your landing page. Fantastic, our API is up and running!

We've made substantial progress in constructing our reproducible cloud environment, eliminating many manual steps from the process. Just imagine having to set up resources manually for three different environments (development, acceptance, and production) through the UI and ensuring their consistency when multiple team members are involved. Thanks to our Infrastructure-as-Code approach, this has become significantly more manageable.

Nevertheless, there's still room for improvement. It would be advantageous to streamline deployment to multiple staging environments using our Terraform files. Ideally, we could incorporate infrastructure deployment into a `CI/CD` pipeline, such as using `GitHub Actions`. However, for now, we've achieved quite a bit in this tutorial, so we'll reserve these enhancements for future tutorials.

I hope you found this `README` helpful, and please feel free to share any feedback you may have!

## 📚 Other useful resources

[Hugging Face model used for the summarization](https://huggingface.co/facebook/bart-large-cnn?text=The+tower+is+324+metres+%281%2C063+ft%29+tall%2C+about+the+same+height+as+an+81-storey+building%2C+and+the+tallest+structure+in+Paris.+Its+base+is+square%2C+measuring+125+metres+%28410+ft%29+on+each+side.+During+its+construction%2C+the+Eiffel+Tower+surpassed+the+Washington+Monument+to+become+the+tallest+man-made+structure+in+the+world%2C+a+title+it+held+for+41+years+until+the+Chrysler+Building+in+New+York+City+was+finished+in+1930.+It+was+the+first+structure+to+reach+a+height+of+300+metres.+Due+to+the+addition+of+a+broadcasting+aerial+at+the+top+of+the+tower+in+1957%2C+it+is+now+taller+than+the+Chrysler+Building+by+5.2+metres+%2817+ft%29.+Excluding+transmitters%2C+the+Eiffel+Tower+is+the+second+tallest+free-standing+structure+in+France+after+the+Millau+Viaduct.)

## Contributions

Contributions and enhancements to **Text-Summarizer-Flask-API-On-Google-Cloud** are welcome! Feel free to fork the repository, make improvements, and submit pull requests.

## License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/OmarKhalil10/DogBreedSpotter/blob/main/LICENSE) file for details.

## Author

[Omar Khalil](https://github.com/OmarKhalil10) 

## Contact

If you have any questions or suggestions, please feel free to [contact me](mailto:omar.khalil498@gmail.com).