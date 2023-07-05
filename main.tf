provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "/tmp/lambda_${random_id.id.hex}.zip"
  source {
    content  = <<EOF
export const handler = async (event) => {
	return {
		statusCode: 200,
		body: JSON.stringify(event, undefined, 4),
	};
}
EOF
    filename = "main.mjs"
  }
}

resource "aws_lambda_function" "tester" {
  function_name = "${random_id.id.hex}-tester"

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  handler = "main.handler"
  runtime = "nodejs18.x"
  role    = aws_iam_role.tester.arn
}

data "aws_iam_policy_document" "tester" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
}

resource "aws_cloudwatch_log_group" "tester" {
  name              = "/aws/lambda/${aws_lambda_function.tester.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "tester" {
  role   = aws_iam_role.tester.id
  policy = data.aws_iam_policy_document.tester.json
}

resource "aws_iam_role" "tester" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_lambda_function_url" "tester" {
  function_name      = aws_lambda_function.tester.function_name
  authorization_type = "NONE"
}

resource "aws_cloudfront_function" "remove_part" {
	name    = "remove_part-${random_id.id.hex}"
	runtime = "cloudfront-js-1.0"
	code    = <<EOF
function handler(event) {
	var request = event.request;
	request.uri = request.uri.replace(/^\/[^/]*\//, "/");
	return request;
}
EOF
}

resource "aws_cloudfront_function" "history_api" {
	name    = "history_api-${random_id.id.hex}"
	runtime = "cloudfront-js-1.0"
	code    = <<EOF
function handler(event) {
	var request = event.request;
	if (request.uri.match(/\/[^./]+\.[^./]+$/) === null) {
		request.uri = "/index.html";
	}
	return request;
}
EOF
}

resource "aws_cloudfront_function" "static_file" {
	name    = "static_file-${random_id.id.hex}"
	runtime = "cloudfront-js-1.0"
	code    = <<EOF
function handler(event) {
	return {
		statusCode: 200,
		statusDescription: "OK",
		body: {
			encoding: "base64",
			data: "${base64encode(trimspace(<<EOT
This is a response defined in Terraform.
It can even include dynamic values: ${aws_lambda_function.tester.arn}
EOT
			))}"
		}
	}
}
EOF
}

resource "aws_cloudfront_distribution" "distribution" {
  origin {
    domain_name              = replace(aws_lambda_function_url.tester.function_url, "/^https?://([^/]*).*/", "$1")
    origin_id                = "tester"
		custom_origin_config {
			http_port = 80
			https_port = 443
			origin_protocol_policy = "https-only"
			origin_ssl_protocols = ["TLSv1.2"]
		}
  }
  origin {
    domain_name              = "invalid.invalid"
    origin_id                = "invalid"
		custom_origin_config {
			http_port = 80
			https_port = 443
			origin_protocol_policy = "http-only"
			origin_ssl_protocols = ["TLSv1.2"]
		}
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  price_class     = "PriceClass_100"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "tester"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "tester"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "https-only"
  }
  ordered_cache_behavior {
    path_pattern     = "/remove_part/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "tester"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
		function_association {
			event_type   = "viewer-request"
			function_arn = aws_cloudfront_function.remove_part.arn
		}

    viewer_protocol_policy = "https-only"
  }
  ordered_cache_behavior {
    path_pattern     = "/history_api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "tester"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
		function_association {
			event_type   = "viewer-request"
			function_arn = aws_cloudfront_function.history_api.arn
		}

    viewer_protocol_policy = "https-only"
  }
  ordered_cache_behavior {
    path_pattern     = "/static_file"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "invalid"

    default_ttl = 0
    min_ttl     = 0
    max_ttl     = 0

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
		function_association {
			event_type   = "viewer-request"
			function_arn = aws_cloudfront_function.static_file.arn
		}

    viewer_protocol_policy = "https-only"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "domain" {
  value = aws_cloudfront_distribution.distribution.domain_name
}
