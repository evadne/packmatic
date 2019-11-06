ExUnit.start()

if System.get_env("TEAMCITY_VERSION") do
  ExUnit.configure(formatters: [TeamCityFormatter])
end

ExUnit.configure(exclude: [external: true])
