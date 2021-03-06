//
//    PortAudioPlayer.cpp: PortAudio player
//    Copyright (C) 2020 Gonzalo José Carracedo Carballal
//
//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU Lesser General Public License as
//    published by the Free Software Foundation, either version 3 of the
//    License, or (at your option) any later version.
//
//    This program is distributed in the hope that it will be useful, but
//    WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU Lesser General Public License for more details.
//
//    You should have received a copy of the GNU Lesser General Public
//    License along with this program.  If not, see
//    <http://www.gnu.org/licenses/>
//

#include <PortAudioPlayer.h>

#define ATTEMPT(expr, what) \
  if ((err = expr) < 0)  \
    throw std::runtime_error("Failed to " + std::string(what) + ": " + std::string(snd_strerror(err)))


using namespace SigDigger;

bool PortAudioPlayer::initialized = false;

bool
PortAudioPlayer::assertPaInitialization(void)
{
  if (!initialized) {
    PaError err = Pa_Initialize();
    initialized = err == paNoError;

    if (initialized)
      atexit(PortAudioPlayer::paFinalizer);
  }

  return initialized;
}

void
PortAudioPlayer::paFinalizer(void)
{
  if (initialized)
    Pa_Terminate();
}

PortAudioPlayer::PortAudioPlayer(
    std::string const &,
    unsigned int rate,
    size_t bufSiz)
  : GenericAudioPlayer(rate)
{
  PaStreamParameters outputParameters;
  PaError pErr;

  if (!assertPaInitialization())
    throw std::runtime_error("Failed to initialize PortAudio library");

  outputParameters.device = Pa_GetDefaultOutputDevice(); /* default output device */
  outputParameters.channelCount = 1;
  outputParameters.sampleFormat = paFloat32;
  outputParameters.suggestedLatency =
      Pa_GetDeviceInfo(outputParameters.device)->defaultHighOutputLatency;
  outputParameters.hostApiSpecificStreamInfo = nullptr;

  pErr = Pa_OpenStream(
     &this->stream,
     nullptr,
     &outputParameters,
     rate,
     bufSiz,
     paClipOff,
     nullptr,
     nullptr);

  if (pErr != paNoError)
      throw std::runtime_error(
          std::string("Failed to open PortAudio stream: ")
          + Pa_GetErrorText(pErr));

  pErr = Pa_StartStream( stream );

  if (pErr != paNoError)
      throw std::runtime_error(
          std::string("Failed to start PortAudio stream: ")
          + Pa_GetErrorText(pErr));
}

bool
PortAudioPlayer::write(const float *buffer, size_t len)
{
  PaError err;

  // TODO: How about writing silence?

  err = Pa_WriteStream(this->stream, buffer, len);
  if (err == paOutputUnderflowed)
    err = Pa_WriteStream(this->stream, buffer, len);

  return err == paNoError;
}

PortAudioPlayer::~PortAudioPlayer()
{
  if (this->stream != nullptr) {
    Pa_StopStream(this->stream);
    Pa_CloseStream(this->stream);
  }
}
