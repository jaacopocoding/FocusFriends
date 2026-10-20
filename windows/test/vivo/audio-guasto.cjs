// L'audio non parte: il compagno non si blocca e continua a parlare.
module.exports = async ({ js, sleep, timer, settings, card }) => {
  const audio = async () => JSON.parse(await js("JSON.stringify(window.__ff.audio())"));
  const state = async () => JSON.parse(await js("JSON.stringify(window.__ff.state())"));
  await sleep(1500);
  // l'audio non parte: lo dice il compagno
  await js("window.__ff.breakAudio()");
  settings.ambientSound = "rain";
  await sleep(1500);
  console.log("audio rotto, il compagno parla?", (await state()).speaking);
};
