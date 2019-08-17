import Foundation
import Combine

public class Retry<Upstream: Publisher, ButFirst: Publisher>: Publisher where ButFirst.Output == Upstream.Output, ButFirst.Failure == Upstream.Failure {
    
    class RetrySubscription<S: Subscriber>: Subscription, Subscriber where S.Input == Output, S.Failure == Failure {
        
        var subscriber: S?
        let shouldRetry: (Input) -> Bool
        var upstream: Upstream?
        var butFirst: ButFirst?
        
        var subscription: Subscription?
        var waitingForSubscription = false
        var remainingDemand = Subscribers.Demand.none
        var executingButFirst = false
        var cancelled = false
        
        init(subscriber: S, shouldRetry: @escaping (Input) -> Bool, upstream: Upstream, butFirst: ButFirst?) {
            self.subscriber = subscriber
            self.shouldRetry = shouldRetry
            self.upstream = upstream
            self.butFirst = butFirst
        }
        
        // MARK: Subscription
        
        func request(_ demand: Subscribers.Demand) {
            Swift.print("Received demand for \(demand.max ?? -1) values")
            self.remainingDemand = demand
            // If we already have a subscription, we forward the demand
            if let subscription = self.subscription {
                Swift.print("We already have a subscription, so forwarding the demand")
                subscription.request(self.remainingDemand)
            // If we don't, we subscribe if we have not been cancelled and we're not waiting for it already
            } else if !self.cancelled && !self.waitingForSubscription {
                Swift.print("We don't have a subscription yet, are not cancelled and not waiting for one, so subscribing upstream")
                self.waitingForSubscription = true
                self.upstream?.subscribe(self)
            }
        }
        
        func cancel() {
            Swift.print("A cancel request came in")
            self.cancelled = true
            self.subscriber = nil
            self.subscription?.cancel()
            self.subscription = nil
        }
        
        // MARK: Subscriber
        // We subscribe to values from upstream.
        
        typealias Input = Upstream.Output
        typealias Failure = Upstream.Failure
        
        func receive(subscription: Subscription) {
            Swift.print("A subscription arrived, so requesting the remaining demand of \(self.remainingDemand.max ?? -1)")
            self.subscription = subscription
            subscription.request(self.remainingDemand)
        }
        
        func receive(_ input: Input) -> Subscribers.Demand {
            Swift.print("Received input \(input); executingButFirst \(self.executingButFirst)")
            // Check if we have to retry
            if !self.executingButFirst && self.shouldRetry(input) {
                // TODO: Check whether cancelling while receiving an input is ok (returning .none might suffice)
                // Cancel the existing upstream subscription
                self.subscription?.cancel()
                self.subscription = nil
                self.waitingForSubscription = true
                if let butFirst = self.butFirst {
                    Swift.print("We have a butFirst, so subscribing to that one")
                    // Subscribe to the butFirst publisher
                    self.executingButFirst = true
                    butFirst.subscribe(self)
                } else {
                    Swift.print("We don't have a butFirst, so subscribing to upstream again")
                    // Request a new upstream subscription
                    self.upstream?.subscribe(self)
                }
                // We don't need any more values from the current subscription
                return .none
            } else {
                if let subscriber = self.subscriber {
                    Swift.print("Forwarding input to subscriber")
                    // Just forward the value if the subscriber is still there
                    // TODO: The subscribers seem to misbehave, because they return a demand of 0
//                    self.remainingDemand = subscriber.receive(input)
//                    Swift.print("Subscriber has a remaining demand of \(self.remainingDemand.max ?? -1)")
//                    return self.remainingDemand
                    let _ = subscriber.receive(input)
                    // Reduce our demand by one if there's a maximum
                    if let max = self.remainingDemand.max {
                        self.remainingDemand = Subscribers.Demand.max(max - 1)
                    }
                }
                // If the subscriber is gone, we were cancelled and don't require any more values
                return .none
            }
        }
        
        func receive(completion: Subscribers.Completion<Failure>) {
            Swift.print("Received completion \(completion); executingButFirst \(self.executingButFirst)")
            if self.executingButFirst {
                self.executingButFirst = false
                switch completion {
                    // If the butFirst publisher finished correctly, we can retry the upstream publisher
                case .finished:
                    self.upstream?.subscribe(self)
                    // If the butFirst publisher failed, we forward the failure to the subscriber
                case .failure(let error):
                    self.subscriber?.receive(completion: .failure(error))
                }
            }
            self.subscriber?.receive(completion: completion)
        }
    }
    
    // MARK: Publisher
    
    public typealias Output = Upstream.Output
    public typealias Failure = Upstream.Failure
    
    let shouldRetry: (Output) -> Bool
    var upstream: Upstream
    var butFirst: ButFirst?
    
    init(if shouldRetry: @escaping (Output) -> Bool, upstream: Upstream, butFirst: ButFirst? = nil) {
        self.shouldRetry = shouldRetry
        self.upstream = upstream
        self.butFirst = butFirst
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        let subscription = RetrySubscription(subscriber: subscriber, shouldRetry: self.shouldRetry, upstream: self.upstream, butFirst: self.butFirst)
        subscriber.receive(subscription: subscription)
    }
}

public extension Publisher {
    
    func retry(if shouldRetry: @escaping (Output) -> Bool) -> Retry<Self, AnyPublisher<Output, Failure>> {
        return Retry(if: shouldRetry, upstream: self)
    }
    
    func retry<ButFirst: Publisher>(butFirst: ButFirst, if shouldRetry: @escaping (Output) -> Bool) -> Retry<Self, ButFirst> {
        return Retry(if: shouldRetry, upstream: self, butFirst: butFirst)
    }
}
