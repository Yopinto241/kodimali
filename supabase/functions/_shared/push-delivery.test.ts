import { deliveryComplete, isUnregisteredDevice } from "./push-delivery.ts";

Deno.test("a bad FCM payload does not disable a valid device", () => {
  if (
    isUnregisteredDevice({
      error: {
        status: "INVALID_ARGUMENT",
        details: [{ "@type": "type.googleapis.com/google.rpc.BadRequest" }],
      },
    })
  ) {
    throw new Error("Valid device would be disabled");
  }
  if (
    !isUnregisteredDevice({
      error: {
        details: [{
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "UNREGISTERED",
        }],
      },
    })
  ) {
    throw new Error("Expired installation was not recognized");
  }
});

Deno.test("successful delivery to one device still retries other transient failures", () => {
  if (deliveryComplete(["receipt"], ["Firebase HTTP 503"])) {
    throw new Error("Partial delivery cannot be terminal");
  }
  if (!deliveryComplete(["receipt"], [])) {
    throw new Error("Complete delivery should finish");
  }
  if (deliveryComplete([], [])) throw new Error("No receipt means no delivery");
});
