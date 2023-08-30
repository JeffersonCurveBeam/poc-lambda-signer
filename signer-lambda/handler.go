package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws/credentials"
	v4 "github.com/aws/aws-sdk-go/aws/signer/v4"
	// https://docs.aws.amazon.com/sdk-for-go/api/aws/signer/v4/
)

type SignedRequest struct {
	Uri     string               `json:"uri"`
	Path    string               `json:"path"`
	Service string               `json:"service"`
	Host    string               `json:"host"`
	Method  string               `json:"method"`
	Body    string               `json:"body"`
	Headers SignedRequestHeaders `json:"headers"`
}

type SignedRequestHeaders struct {
	Host              string `json:"host"`
	ContentType       string `json:"content-type"`
	ContentLength     string `json:"content-length"`
	Authorization     string `json:"authorization"`
	XAmzDate          string `json:"x-amz-date"`
	XAmzSecurityToken string `json:"x-amz-security-token"`
}

// const uri = `${awsProtocol}://${awsHost}${req.url}`;

// path: '/datastore/f0595a94cc2348b5b7112fd1b16df1f2/imageSet/a42f96aa6ec53ff88f0fd52a314a54d1/getImageFrame',
// service: 'medical-imaging',
// host: 'runtime-medical-imaging.ap-southeast-2.amazonaws.com',
// method: 'POST',
// body: '{"imageFrameId":"b2fe4413f159fd3bb6cc60c5950d21bd"}',
// headers: {
//   Host: 'runtime-medical-imaging.ap-southeast-2.amazonaws.com',
//   'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
//   'Content-Length': 51,
//   'X-Amz-Security-Token': 'IQoJb3JpZ2luX2VjEL3//////////wEaDmFwLXNvdXRoZWFzdC0yIkcwRQIhAIBRaUCEbhunqqhLdZIrvVxznoTo4cNMV3sVM+TIR3DzAiAUsxdLmON2kFQwKohtgTtTI3q2YrsbUZeNDNYbUWbv+yr5AgiG//////////8BEAIaDDQ0NDYwMTEyMDcwNCIMdh+lBKWFCawa9j5dKs0CMHZEf3YWvosETp8DVkz/UvmMFzQtppYHxXxuYd2x2wW/1TNXFuPvEGnJJD4AX/35fvUYphba6ZKiPG+mmxiqJ/FyCX/7XvFrk9dzdqW0I9pXonueSARPZG5IOJhfzDqE0M5eBfs2Yn2gA7UlJpXlnRlz7s+dNKuHX/SuWUi/QTuuCQhmU6cxqN2cqpOh3rkIMPkUhI0xOpSczICF/2ojE8YGPvdS62L2DKtC+dhnB1vlmtaLgEH/g03GsKR0S/c3M43QDW5rpJiXKL+dfzzgtoSQfQQaOfQIRDnsZYZwk6LGmJLgmv0ZymLvt2mk+qFrW8ob33BlAB2iWtoGdh1TJGcTc0ZPVRfGoaq0TKRdnfQnyUFMlKMmJfZrboabNbQLGTyRk4OWUsFrHDdWC1+awyM/peDRo0S9RjLfwRICwZepG17u/RQyWR3JziHEMOrRsKcGOqcBCzvbLU9nBqFlKsyL4g1vd++D5AQ7+FugNbzZOVYMTtamWE6lDPduiKFw2ueQ9V5ndkqgGKJZ0c2hoY752QMgslmwo/Z/KDoH6HtRFNeLuDKfkEu1KUuIXsWZ8Z2xcxpw8G4brmMg9u1CqN/7R6t2z3AZmfLdDSNGn+KQoos2IV4wFxR9rp7KsnMPtOZ87EUQYqqNoLAC8i4wVbmTIb09fy/QgtzZvxs=',
//   'X-Amz-Date': '20230828T050337Z',
//   Authorization: 'AWS4-HMAC-SHA256 Credential=ASIAWPBCKW7AJL4NVNHH/20230828/ap-southeast-2/medical-imaging/aws4_request, SignedHeaders=content-length;content-type;host;x-amz-date;x-amz-security-token, Signature=fe4d9a8c19832d2ed8a703d56bf92ea709f5cf6b422a977a74568d8b5cfa7170'

func main() {
	lambda.Start(handler)
}

func handler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	signedRequestSerialized, err := sign(req.HTTPMethod, req.Path, req.Body)

	if err != nil {
		fmt.Printf("Error signing request: %v\n", err)
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Body:       err.Error(),
		}, nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       signedRequestSerialized,
	}, nil
}

func sign(method string, url string, body string) (string, error) {
	// Create new HTTP request object
	request, err := http.NewRequest(method, url, nil)
	if err != nil {
		return "", err
	}

	// Create V4 AWS signer
	lambdaCredentials := credentials.NewStaticCredentials(
		os.Getenv("AWS_ACCESS_KEY_ID"),
		os.Getenv("AWS_SECRET_ACCESS_KEY"),
		os.Getenv("AWS_SESSION_TOKEN"),
	)

	signer := v4.NewSigner(lambdaCredentials)

	// Sign HTTP request - `request` parameter is mutated
	_, err = signer.Sign(
		request,
		strings.NewReader(body),
		"medical-imaging",
		"ap-southeast-2",
		time.Now(),
	)
	if err != nil {
		return "", err
	}

	fmt.Printf("request headers: %v\n", request.Header)

	// Create signed request object
	signedRequest := SignedRequest{
		Uri:     fmt.Sprintf("https://%s%s", os.Getenv("AWS_HOST"), url),
		Path:    url,
		Service: "medical-imaging",
		Host:    os.Getenv("AWS_HOST"),
		Method:  method,
		Body:    body,
		Headers: SignedRequestHeaders{
			Host:              request.Header.Get("Host"),
			ContentType:       request.Header.Get("Content-Type"),
			ContentLength:     request.Header.Get("Content-Length"),
			Authorization:     request.Header.Get("Authorization"),
			XAmzDate:          request.Header.Get("X-Amz-Date"),
			XAmzSecurityToken: request.Header.Get("X-Amz-Security-Token"),
		},
	}

	signedRequestSerialised, err := json.Marshal(signedRequest)
	if err != nil {
		return "", err
	}

	return string(signedRequestSerialised), nil
}
