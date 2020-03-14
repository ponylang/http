variable "google_project" {
  description = "project you wanna use."
}

variable "credentials_file" {}

variable "google_region" {
  description = "google compute region"
  default     = "europe-west3"
}

variable "google_zone" {
  description = "zone"
  default     = "europe-west3-a"
}

