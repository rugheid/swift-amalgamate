# Amalgamate

_Amalgamate: combine or unite to form one organization or structure._

The Amalgamate package extends the Combine framework with handy utilities.

## Installation

Amalgamate is only available as a Swift Package.
If you're using Xcode 11, you can add it using `File > Swift Packages > Add Package Dependency...`

## Usage

Import the Amalgamate package: `import Amalgamate`.

### Retry

The Retry publisher retries an upstream publisher when a given condition is met. You can pass a publisher to run before retrying.

```swift
upstreamPublisher.retry { value in
    return indicatesFailure(value)
}
```
Restarts the upstream publisher if the value it sent indicates failure. Failures will just be propagated downstream.

```swift
apiCallPublisher.retry(butFirst: authenticatePublisher) { response in
    return response.statusCode == 401
}
```
Restarts the API call publisher if the response indicates being unauthorized, but will first authenticate using the authenticate publisher.
