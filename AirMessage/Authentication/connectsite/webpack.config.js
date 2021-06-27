const path = require("path");
const CopyPlugin = require("copy-webpack-plugin");

module.exports = {
	entry: "./index.js",
	target: "es5",
	mode: "production",
	output: {
		path: path.resolve(__dirname, "build"),
		filename: "index.js",
		assetModuleFilename: "res/[hash][ext][query]",
		publicPath: "",
		clean: true
	},
	module: {
		rules: [
			{
				test: /\.m?js$/,
				exclude: /node_modules/,
				use: {
					loader: "babel-loader",
					options: {
						presets: ["@babel/preset-env"]
					}
				}
			}
		]
	},
	plugins: [
		new CopyPlugin({
			patterns: [
				{from: "index.html"},
				{from: "index.css"},
				{from: "node_modules/firebaseui/dist/firebaseui.css"},
				{from: "banner.png"}
			],
		})
	]
};