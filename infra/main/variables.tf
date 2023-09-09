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

variable "repository" {
  description = "The name of the Artifact Registry repository to be created"
  type        = string
  default     = "docker-repository"
}

variable "docker_image" {
  description = "The name of the Docker image in the Artifact Registry repository to be deployed to Cloud Run"
  type        = string
  default     = "summarizer-app"
}

variable "first_time" {
  description = "Boolean flag to indicate if this is the first time the application is running. If so, the cloud run step is omitted"
  type        = bool
  default     = false
}