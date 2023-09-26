# Example code to show different scenarios for CloudFront functions

## Deploy

* ```terraform init```
* ```terraform apply```

## Usage

### Rewrite request path

* Problem: path pattern: ```/api/*``` still includes the prefix: ```/api/test``` => ```/api/test```
* Remove it with a function: ```/remove_path/test``` => ```/test```

### HTML5 History API support

* Any path without an extension goes to ```/index.html```
* ```/history_api/main.js``` => ```/history_api/main.js```
* ```/history_api/orders``` => ```/index.html```

### Static file

* ```/static_file``` returns static contents defined in the function without touching the origin

## Cleanup

* ```terraform destroy```
