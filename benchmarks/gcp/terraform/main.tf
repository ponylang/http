provider "google" {
  version = "3.12.0"

  project     = var.google_project
  region      = var.google_region
  zone        = var.google_zone
  credentials = file(var.credentials_file)
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}


resource "google_compute_instance" "bench_server" {
  name         = "pony-http-bench-server"
  machine_type = "n1-standard-8"
  zone         = var.google_zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-minimal-1804-lts"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name

    access_config {
      // Include this section to give the VM an external ip address
    }
  }
}

resource "google_compute_instance" "bench_client" {
  name         = "pony-http-bench-client"
  machine_type = "n1-standard-8"
  zone         = var.google_zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-minimal-1804-lts"
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Include this section to give the VM an external ip address
    }
  }
}


