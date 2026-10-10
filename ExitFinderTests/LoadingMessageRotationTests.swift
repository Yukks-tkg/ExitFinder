import Testing
@testable import ExitFinder

@MainActor
struct LoadingMessageRotationTests {
    @Test func doesNotStartWhenLoadingHasEnded() async {
        var sleepCount = 0
        var advanceCount = 0

        await ContentView.rotateLoadingMessages(
            isLoading: { false },
            sleep: { sleepCount += 1 },
            advance: { advanceCount += 1 }
        )

        #expect(sleepCount == 0)
        #expect(advanceCount == 0)
    }

    @Test func advancesOnceAfterEachSuccessfulWait() async {
        var sleepCount = 0
        var advanceCount = 0

        await ContentView.rotateLoadingMessages(
            isLoading: { advanceCount < 3 },
            sleep: { sleepCount += 1 },
            advance: { advanceCount += 1 }
        )

        #expect(sleepCount == 3)
        #expect(advanceCount == 3)
    }

    @Test func doesNotAdvanceWhenLoadingEndsDuringWait() async {
        var loading = true
        var advanceCount = 0

        await ContentView.rotateLoadingMessages(
            isLoading: { loading },
            sleep: { loading = false },
            advance: { advanceCount += 1 }
        )

        #expect(advanceCount == 0)
    }

    @Test func exitsAfterCancelledWaitWithoutRetrying() async {
        var sleepCount = 0
        var advanceCount = 0

        // The bound makes an ignored cancellation fail assertions instead of hanging.
        await ContentView.rotateLoadingMessages(
            isLoading: { sleepCount < 3 },
            sleep: {
                sleepCount += 1
                throw CancellationError()
            },
            advance: { advanceCount += 1 }
        )

        #expect(sleepCount == 1)
        #expect(advanceCount == 0)
    }

    @Test func alreadyCancelledTaskDoesNotWaitOrAdvance() async {
        var sleepCount = 0
        var advanceCount = 0

        // Both the test and task use MainActor, so cancellation precedes task entry.
        let task = Task { @MainActor in
            await ContentView.rotateLoadingMessages(
                isLoading: { sleepCount < 3 },
                sleep: { sleepCount += 1 },
                advance: { advanceCount += 1 }
            )
        }
        task.cancel()
        await task.value

        #expect(sleepCount == 0)
        #expect(advanceCount == 0)
    }

    @Test func cancellationDuringNonThrowingWaitPreventsAdvance() async {
        var sleepCount = 0
        var advanceCount = 0

        let task = Task { @MainActor in
            await ContentView.rotateLoadingMessages(
                isLoading: { sleepCount < 3 },
                sleep: {
                    sleepCount += 1
                    withUnsafeCurrentTask { $0?.cancel() }
                },
                advance: { advanceCount += 1 }
            )
        }
        await task.value

        #expect(sleepCount == 1)
        #expect(advanceCount == 0)
    }
}
