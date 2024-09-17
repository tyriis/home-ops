// source: https://github.com/Koenkk/zigbee2mqtt/issues/23577

const exposes = require("zigbee-herdsman-converters/lib/exposes")
const e = exposes.presets
const ea = exposes.access

const lumi = require("zigbee-herdsman-converters/lib/lumi")
const { manufacturerCode } = lumi

const fzLocal = {
  fp11_presence: {
    cluster: "manuSpecificLumi",
    type: ["readResponse", "attributeReport"],
    convert: (model, msg, publish, options, meta) => {
      console.info("msg.data=", msg.data)
      payload = {}
      for (const key in msg.data) {
        value = msg.data[key]
        if (key == "322") {
          payload["presence"] = value == 1
        }
        if (key == "351") {
          // distance in cm
          payload["target_distance"] = 0.01 * value
        }
        if (key == "352") {
          payload["region_event"] = value // is this a region event?
        }
      }
      return payload
    },
  },
}

const definition = {
  zigbeeModel: ["lumi.sensor_occupy.agl1"],
  model: "lumi.sensor_occupy.agl1",
  vendor: "Aqara",
  description: "Presence sensor FP1E",
  extend: [lumi.modernExtend.lumiZigbeeOTA()],
  fromZigbee: [fzLocal.fp11_presence, lumi.fromZigbee.lumi_specific],
  toZigbee: [lumi.toZigbee.lumi_presence],
  exposes: [
    e.presence().withAccess(ea.STATE_GET),
    e.device_temperature(),
    e.power_outage_count(),
    e
      .numeric("target_distance", ea.STATE_GET)
      .withUnit("m")
      .withDescription("Target distance"),
  ],
  configure: async (device, coordinatorEndpoint) => {
    device.softwareBuildID = `${device.applicationVersion}`
    device.save()

    const endpoint = device.getEndpoint(1)
    await endpoint.read("manuSpecificLumi", [0x0142], {
      manufacturerCode: manufacturerCode,
    })
  },
  meta: {},
}

module.exports = definition
