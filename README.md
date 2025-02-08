# Self-Hosted Database MVP Demo

*Please not that some extra configuration will be needed for the Terraform e.g. deploy in a private subnet or improve SG*

TL;DR: Can I run my own database client with increased concurrent connections in order reduce the huge cost of RDS vertical scaling

This project is an MVP to explore whether a self‑hosted database solution can overcome the connection limitations of managed RDS instances—and possibly do so at a lower cost. 
In this demo, I’ve built a solution that runs a Dockerized MongoDB instance on an EC2 server with an attached EBS volume. 
A simple Go wrapper service (with built‑in connection pooling) acts as the API layer to handle many concurrent read requests.

## Concept Overview

**The Challenge:**  
Managed RDS databases often run into issues when handling a large number of connections—even for simple read operations. 
While RDS can be scaled vertically or horizontally, this sometimes comes at a high cost.

**The Idea:**  
I wanted to see if I could build a self‑hosted solution using:
- **Dockerized MongoDB:** Running on an EC2 instance with data persisted on an EBS volume.
- **A Go Wrapper Service:** This service provides a simple API and leverages connection pooling (via the official MongoDB driver) to better handle a high number of concurrent connections.

By comparing this approach with a managed RDS solution, I aim to evaluate both the cost and performance (especially connection capacity) of each.

**What’s Included in the MVP:**
- **Self‑Hosted Database:** MongoDB running in a Docker container with persistent storage on an EBS volume.
- **Go Wrapper Service:** A small Go application that connects to MongoDB using connection pooling and exposes an HTTP endpoint.
- **Infrastructure as Code (Terraform):**  
  - A free‑tier EC2 instance (t2.micro) in the default VPC.
  - A separate, cost‑effective 30 GB gp3 EBS volume that is mounted on the instance.
  - An AWS Data Lifecycle Manager (DLM) policy to automatically take daily snapshots of the EBS volume.
  - Security groups that allow SSH, HTTP (port 8080), and MongoDB (port 27017) access.

## Pricing Estimation Comparison

Here’s a rough monthly cost estimation (without any savings plan) for both a managed RDS solution and a self‑hosted EC2 solution. Note that these numbers are for a moderate workload scenario and might vary in production:

| Component                     | RDS (Managed)                         | Self‑Hosted on EC2 with EBS          |
|-------------------------------|---------------------------------------|--------------------------------------|
| **Compute Instance**          | ~\$146/month (db.m5.large on‑demand)   | ~\$70/month (m5.large on‑demand)       |
| **Storage (100 GB)**          | ~\$10/month                           | ~\$8/month                           |
| **Backup/Snapshot Overhead**  | Often included/free (up to quota)     | ~\$5/month (approximate)             |
| **Total (Approx.)**           | **~\$156/month**                      | **~\$83/month**                      |

> **Note:**  
> For this MVP/demo, I’m using free‑tier eligible components (like a t2.micro instance and a 30 GB EBS volume). Production setups may require larger resources, which would affect these cost estimates.

## How to Run the MVP

1. **Deploy the Infrastructure:**
   - Ensure you have Terraform installed.
   - Update the Terraform configuration with your SSH key and Docker Hub username.
   - Run the following commands in the project directory:
     ```bash
     terraform init
     terraform plan
     terraform apply
     ```
   This will provision the EC2 instance, attach and mount the EBS volume, and configure the automated snapshot policy via AWS DLM.

2. **Build and Deploy the Docker Images:**
   - Build the Go wrapper image (assuming your project consists of `main.go`, `go.mod`, and `go.sum`):
     ```bash
     docker build -t your-dockerhub-username/go-wrapper:latest .
     ```
   - Push the image to Docker Hub:
     ```bash
     docker push your-dockerhub-username/go-wrapper:latest
     ```
   - The Terraform user data script on the EC2 instance is set up to pull this image and run the container along with a MongoDB container.

3. **Test the Service:**
   - Once the EC2 instance is running, access the Go wrapper service on port 8080.
   - You can use tools like `curl` or your web browser to send HTTP requests to the service and observe how it handles many concurrent connections.

## Finally 

The self‑hosted solution gives full control over configuration and can potentially handle a larger number of connections 
through custom tuning and connection pooling. 
However, it does require additional operational effort (like managing snapshots, backups, and scaling).

---

*Happy coding and benchmarking!*
