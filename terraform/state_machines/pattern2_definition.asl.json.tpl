{
    "StartAt": "OCRStep",
    "States": {
        "OCRStep": {
            "Type": "Task",
            "Resource": "${ocr_function_arn}",
            "Parameters": {
                "execution_arn.$": "$$.Execution.Id",
                "document.$": "$.document"
            },
            "ResultPath": "$.OCRResult",
            "Retry": [
                {
                    "ErrorEquals": [
                        "Sandbox.Timedout",
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException",
                        "Lambda.TooManyRequestsException",
                        "ServiceQuotaExceededException",
                        "ThrottlingException",
                        "ProvisionedThroughputExceededException",
                        "RequestLimitExceeded"
                    ],
                    "IntervalSeconds": 2,
                    "MaxAttempts": 2,
                    "BackoffRate": 2
                }
            ],
            "Next": "ClassificationStep"
        },
        "ClassificationStep": {
            "Type": "Task",
            "Resource": "${classification_function_arn}",
            "Parameters": {
                "execution_arn.$": "$$.Execution.Id",
                "OCRResult.$": "$.OCRResult"
            },
            "ResultPath": "$.ClassificationResult",
            "Retry": [
                {
                    "ErrorEquals": [
                        "Sandbox.Timedout",
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException",
                        "Lambda.TooManyRequestsException",
                        "ServiceQuotaExceededException",
                        "ThrottlingException",
                        "ProvisionedThroughputExceededException",
                        "RequestLimitExceeded"
                    ],
                    "IntervalSeconds": 2,
                    "MaxAttempts": 10,
                    "BackoffRate": 2
                }
            ],
            "Next": "ProcessSections"
        },
        "ProcessSections": {
            "Type": "Map",
            "ItemsPath": "$.ClassificationResult.document.sections",
            "ItemSelector": {
                "execution_arn.$": "$$.Execution.Id",
                "document.$": "$.ClassificationResult.document",
                "section_id.$": "$$.Map.Item.Value"
            },
            "MaxConcurrency": 10,
            "Iterator": {
                "StartAt": "ExtractionStep",
                "States": {
                    "ExtractionStep": {
                        "Type": "Task",
                        "Resource": "${extraction_function_arn}",
                        "ResultPath": "$.ExtractionResult",
                        "Retry": [
                            {
                                "ErrorEquals": [
                                    "Sandbox.Timedout",
                                    "Lambda.ServiceException",
                                    "Lambda.AWSLambdaException",
                                    "Lambda.SdkClientException",
                                    "Lambda.TooManyRequestsException",
                                    "ServiceQuotaExceededException",
                                    "ThrottlingException",
                                    "ProvisionedThroughputExceededException",
                                    "RequestLimitExceeded"
                                ],
                                "IntervalSeconds": 2,
                                "MaxAttempts": 10,
                                "BackoffRate": 2
                            }
                        ],
                        "Next": "AssessmentStep"
                    },
                    "AssessmentStep": {
                        "Type": "Task",
                        "Resource": "${assessment_function_arn}",
                        "Parameters": {
                            "execution_arn.$": "$$.Execution.Id",
                            "document.$": "$.ExtractionResult.document",
                            "section_id.$": "$.ExtractionResult.section_id"
                        },
                        "ResultPath": "$",
                        "Retry": [
                            {
                                "ErrorEquals": [
                                    "Sandbox.Timedout",
                                    "Lambda.ServiceException",
                                    "Lambda.AWSLambdaException",
                                    "Lambda.SdkClientException",
                                    "Lambda.TooManyRequestsException",
                                    "ServiceQuotaExceededException",
                                    "ThrottlingException",
                                    "ProvisionedThroughputExceededException",
                                    "RequestLimitExceeded"
                                ],
                                "IntervalSeconds": 2,
                                "MaxAttempts": 10,
                                "BackoffRate": 2
                            }
                        ],
                        "Next": "SectionComplete"
                    },
                    "SectionComplete": {
                        "Type": "Pass",
                        "End": true
                    }
                }
            },
            "ResultPath": "$.ExtractionResults",
            "Next": "ProcessResultsStep"
        },
        "ProcessResultsStep": {
            "Type": "Task",
            "Resource": "${process_results_function_arn}",
            "Parameters": {
                "execution_arn.$": "$$.Execution.Id",
                "ClassificationResult.$": "$.ClassificationResult",
                "ExtractionResults.$": "$.ExtractionResults"
            },
            "ResultPath": "$.Result",
            "Retry": [
                {
                    "ErrorEquals": [
                        "Sandbox.Timedout",
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException",
                        "Lambda.TooManyRequestsException",
                        "ServiceQuotaExceededException",
                        "ThrottlingException",
                        "ProvisionedThroughputExceededException",
                        "RequestLimitExceeded"
                    ],
                    "IntervalSeconds": 2,
                    "MaxAttempts": 10,
                    "BackoffRate": 2
                }
            ],
            "Next": "CheckHITLRequired"
        },
        "CheckHITLRequired": {
            "Type": "Choice",
            "Choices": [
                {
                    "Variable": "$.Result.hitl_triggered",
                    "BooleanEquals": true,
                    "Next": "HITLReview"
                }
            ],
            "Default": "SummarizationStep"
        },
        "HITLReview": {
            "Type": "Task",
            "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
            "Parameters": {
                "FunctionName": "${hitl_wait_function_arn}",
                "Payload": {
                    "taskToken.$": "$$.Task.Token",
                    "Payload.$": "$"
                }
            },
            "ResultPath": "$.HITLWaitResult",
            "Retry": [
                {
                    "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.SdkClientException",
                        "Lambda.TooManyRequestsException",
                        "ServiceQuotaExceededException",
                        "ThrottlingException",
                        "ProvisionedThroughputExceededException",
                        "RequestLimitExceeded"
                    ],
                    "IntervalSeconds": 2,
                    "MaxAttempts": 10,
                    "BackoffRate": 2
                }
            ],
            "Next": "HITLStatusUpdate"
        },
        "HITLStatusUpdate": {
            "Type": "Task",
            "Resource": "${hitl_status_update_function_arn}",
            "Parameters": {
                "Result.$": "$.Result",
                "HITLWaitResult.$": "$.HITLWaitResult"
            },
            "ResultPath": "$.HITLStatusResult",
            "Retry": [
                {
                    "ErrorEquals": [
                        "Lambda.ServiceException",
                        "Lambda.SdkClientException",
                        "Lambda.TooManyRequestsException",
                        "ServiceQuotaExceededException",
                        "ThrottlingException",
                        "ProvisionedThroughputExceededException",
                        "RequestLimitExceeded"
                    ],
                    "IntervalSeconds": 2,
                    "MaxAttempts": 10,
                    "BackoffRate": 2
                }
            ],
            "Next": "SummarizationStep"
        },
        "SummarizationStep": {
            "Type": "Task",
            "Resource": "${summarization_function_arn}",
            "Parameters": {
                "execution_arn.$": "$$.Execution.Id",
                "document.$": "$.Result.document"
            },
            "ResultPath": "$.Result",
            "OutputPath": "$.Result.document",
            "Retry": [
                {
                    "ErrorEquals": [
                        "Sandbox.Timedout",
                        "Lambda.ServiceException",
                        "Lambda.AWSLambdaException",
                        "Lambda.SdkClientException",
                        "Lambda.TooManyRequestsException",
                        "ServiceQuotaExceededException",
                        "ThrottlingException",
                        "ProvisionedThroughputExceededException",
                        "RequestLimitExceeded"
                    ],
                    "IntervalSeconds": 2,
                    "MaxAttempts": 10,
                    "BackoffRate": 2
                }
            ],
            "Next": "WorkflowComplete"
        },
        "WorkflowComplete": {
            "Type": "Pass",
            "End": true
        }
    }
}
